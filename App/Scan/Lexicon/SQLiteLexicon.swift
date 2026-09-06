import Foundation
import UIKit
import SQLite3
import os

// The point of using a manual dictionary over the IOS native one is that it allows for lemmatization
// A user scanning a conjugated or pluralized word on a poster should collect the root form
// as this is a reasonable deduplication key.

// MARK: - Lexicon Entry

/// A resolved word from the lexicon database
struct LexiconEntry: Sendable {
    let wordId: Int64
    let lemma: String
    let translation: String?
    let language: Language
    let isFlagged: Bool
    let isBaseVocab: Bool
}

// MARK: - SQLite Lexicon

/// High-performance lexicon backed by SQLite.
/// Thread-safe and memory-efficient for large vocabularies.
final class SQLiteLexicon: LexiconResolving, @unchecked Sendable {
    
    // MARK: - Properties
    
    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.app.lexicon", qos: .userInitiated)
    
    /// Prepared statements for performance
    private var lookupByFormStmt: OpaquePointer?
    private var lookupByLemmaStmt: OpaquePointer?
    private var lookupByTranslationStmt: OpaquePointer?
    private var searchStmt: OpaquePointer?
    
    /// In-memory cache for hot words (optional optimization)
    private var cache: [String: LexiconEntry] = [:]
    private let cacheLimit = 1000
    private let cacheLock = NSLock()
    
    // MARK: - Initialization
    
    /// File URL for the copied database (SQLite needs file access, not in-memory data)
    private let dbFileURL: URL
    
    init?(assetName: String = "lexicon") {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        self.dbFileURL = cacheDir.appendingPathComponent("\(assetName).sqlite")
    }

    /// Call this asynchronously to load data off the main thread
    func prepareDatabase(assetName: String) async {
        await Task.detached(priority: .userInitiated) { [self] in
            let t0 = CFAbsoluteTimeGetCurrent()

            // SQLite requires a file path - copy from asset catalog to cache directory
            guard let asset = NSDataAsset(name: assetName) else {
                Log.lexicon.error("Asset '\(assetName, privacy: .public)' not found in asset catalog")
                return
            }
            let t1 = CFAbsoluteTimeGetCurrent()
            
            // Copy database to cache if not present or outdated
            if !Self.copyDatabaseIfNeeded(asset: asset, to: self.dbFileURL) {
                Log.lexicon.error("Failed to copy lexicon database to cache")
                return
            }
            let t2 = CFAbsoluteTimeGetCurrent()
            
            guard sqlite3_open_v2(
                self.dbFileURL.path,
                &self.db,
                SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX,
                nil
            ) == SQLITE_OK else {
                Log.lexicon.error("Failed to open lexicon database")
                return
            }
            let t3 = CFAbsoluteTimeGetCurrent()
            
            self.prepareStatements()
            let t4 = CFAbsoluteTimeGetCurrent()

            #if DEBUG
            Log.lexicon.debug("Initialized from asset catalog")
            Log.lexicon.debug("[SQLiteLexicon.init] NSDataAsset: \(String(format: "%.1f", (t1-t0)*1000), privacy: .public)ms | copyIfNeeded: \(String(format: "%.1f", (t2-t1)*1000), privacy: .public)ms | sqlite3_open: \(String(format: "%.1f", (t3-t2)*1000), privacy: .public)ms | prepareStmts: \(String(format: "%.1f", (t4-t3)*1000), privacy: .public)ms | total: \(String(format: "%.1f", (t4-t0)*1000), privacy: .public)ms")
            #endif
        }.value
    }
    
    /// Copies the database from asset data to a file URL if needed
    private static func copyDatabaseIfNeeded(asset: NSDataAsset, to url: URL) -> Bool {
        let fileManager = FileManager.default
        
        if fileManager.fileExists(atPath: url.path) {
            if let attrs = try? fileManager.attributesOfItem(atPath: url.path),
               let fileSize = attrs[.size] as? Int,
               fileSize == asset.data.count {
                return true
            }
            try? fileManager.removeItem(at: url)
        }
        
        do {
            try asset.data.write(to: url, options: .atomic)
            return true
        } catch {
            Log.lexicon.error("Write failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
    
    deinit {
        sqlite3_finalize(lookupByFormStmt)
        sqlite3_finalize(lookupByLemmaStmt)
        sqlite3_finalize(lookupByTranslationStmt)
        sqlite3_finalize(searchStmt)
        sqlite3_close(db)
    }
    
    // MARK: - LexiconResolving
    
    func resolve(observed: String, normalized: String, language: Language) -> WordResolution {
        guard language != .english else {
            return passthroughResolution(observed: observed, normalized: normalized, language: language)
        }
        
        let lookupKey = normalized.lowercased()
        
        if let cached = getCached(lookupKey, language: language) {
            return WordResolution(
                observed: observed,
                normalized: normalized,
                language: language,
                lemma: cached.lemma,
                translation: cached.translation,
                bounds: nil
            )
        }
        
        if let entry = lookupWord(form: lookupKey, language: language) {
            setCache(lookupKey, language: language, entry: entry)
            return WordResolution(
                observed: observed,
                normalized: normalized,
                language: language,
                lemma: entry.lemma,
                translation: entry.translation,
                bounds: nil
            )
        }
        
        return passthroughResolution(observed: observed, normalized: normalized, language: language)
    }
    
    // MARK: - Lookup Methods
    
    private func lookupWord(form: String, language: Language) -> LexiconEntry? {
        queue.sync {
            guard let stmt = lookupByFormStmt else { return nil }
            
            sqlite3_reset(stmt)
            sqlite3_bind_text(stmt, 1, form, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, language.databaseCode, -1, SQLITE_TRANSIENT)
            
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            return extractEntry(from: stmt, language: language)
        }
    }
    
    func lookupLemma(_ lemma: String, language: Language) -> LexiconEntry? {
        guard language != .english else { return nil }
        
        return queue.sync {
            guard let stmt = lookupByLemmaStmt else { return nil }
            
            sqlite3_reset(stmt)
            sqlite3_bind_text(stmt, 1, lemma.lowercased(), -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, language.databaseCode, -1, SQLITE_TRANSIENT)
            
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            return extractEntry(from: stmt, language: language)
        }
    }
    
    func lookupByTranslation(_ englishWord: String, language: Language) -> [LexiconEntry] {
        guard language != .english else { return [] }
        
        return queue.sync {
            guard let stmt = lookupByTranslationStmt else { return [] }
            
            sqlite3_reset(stmt)
            sqlite3_bind_text(stmt, 1, englishWord.lowercased(), -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, language.databaseCode, -1, SQLITE_TRANSIENT)
            
            var entries: [LexiconEntry] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let wordId = sqlite3_column_int64(stmt, 0)
                let lemma = String(cString: sqlite3_column_text(stmt, 1))
                let translation: String? = sqlite3_column_type(stmt, 2) != SQLITE_NULL
                    ? String(cString: sqlite3_column_text(stmt, 2)) : nil
                let isBaseVocab = sqlite3_column_int(stmt, 3) != 0
                entries.append(LexiconEntry(wordId: wordId, lemma: lemma, translation: translation,
                                            language: language, isFlagged: false, isBaseVocab: isBaseVocab))
            }
            return entries
        }
    }
    
    // MARK: - Autocomplete Search
    
    /// Search for words matching a query in the lemma or translation.
    /// Results are sorted with nouns (article-prefixed words) prioritized over
    /// non-noun matches, since the app focuses on concrete objects.
    func searchByPrefix(_ query: String, language: Language, limit: Int = 20) -> [LexiconEntry] {
        guard language != .english else { return [] }
        guard !query.isEmpty else { return [] }
        
        // Strip article from query if user typed e.g. "el gato" or "la casa"
        let strippedQuery = language.strippingArticle(from: query)
        
        return queue.sync {
            guard let stmt = searchStmt else { return [] }
            
            sqlite3_reset(stmt)
            
            // Build article-prefixed patterns for root matches
            let articles = language.articles
            let barePattern = "\(strippedQuery.lowercased())%"
            var patterns = [barePattern]
            
            for article in articles {
                patterns.append("\(article) \(strippedQuery.lowercased())%")
            }
            
            // Pad to exactly 9 patterns (matching the 9 root LIKE slots in SQL)
            while patterns.count < 9 {
                patterns.append("")  // Empty string won't match anything
            }
            
            // Bind root patterns (?1..?9)
            for (i, pattern) in patterns.prefix(9).enumerated() {
                sqlite3_bind_text(stmt, Int32(i + 1), pattern, -1, SQLITE_TRANSIENT)
            }
            
            // ?10: translation prefix match
            sqlite3_bind_text(stmt, 10, "\(strippedQuery.lowercased())%", -1, SQLITE_TRANSIENT)
            // ?11: translation contains match (for comma-separated lists)
            sqlite3_bind_text(stmt, 11, "%, \(strippedQuery.lowercased())%", -1, SQLITE_TRANSIENT)
            // ?12: language code
            sqlite3_bind_text(stmt, 12, language.databaseCode, -1, SQLITE_TRANSIENT)
            // ?13: bare query for exact match ordering
            sqlite3_bind_text(stmt, 13, strippedQuery.lowercased(), -1, SQLITE_TRANSIENT)
            // ?14: limit
            sqlite3_bind_int(stmt, 14, Int32(limit))
            
            var rawResults: [LexiconEntry] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                rawResults.append(extractEntry(from: stmt, language: language))
            }
            
            return rawResults.sorted { a, b in
                let aHasArticle = language.hasLeadingArticle(in: a.lemma)
                let bHasArticle = language.hasLeadingArticle(in: b.lemma)
                if aHasArticle != bHasArticle {
                    return aHasArticle  // article-prefixed words first
                }
                // Within same group, prefer base vocab, then shorter words
                if a.isBaseVocab != b.isBaseVocab {
                    return a.isBaseVocab
                }
                return a.lemma.count < b.lemma.count
            }
        }
    }

    /// Fix #5: Async version of searchByPrefix that runs the SQLite query off the main thread.
    /// Use this from UI search handlers to avoid blocking the main actor.
    func searchByPrefixAsync(_ query: String, language: Language, limit: Int = 20) async -> [LexiconEntry] {
        let query = query
        let language = language
        let limit = limit
        return await Task.detached(priority: .userInitiated) { [self] in
            self.searchByPrefix(query, language: language, limit: limit)
        }.value
    }
    
    // MARK: - Batch Lookup
    
    /// Batch-lookup translations for multiple lemmas in a single SQLite query.
    /// Replaces N individual `lookupLemma` calls (each doing `queue.sync` + a
    /// potentially unindexed table scan) with one query that scans the table once.
    /// This is the difference between ~20 s and <0.1 s at startup.
    func batchLookupTranslations(lemmas: [String], language: Language) -> [String: String] {
        guard language != .english, !lemmas.isEmpty else { return [:] }
        
        return queue.sync {
            guard db != nil else { return [:] }
            
            var result: [String: String] = [:]
            
            // SQLite has a variable limit (default 999). Process in chunks.
            let chunkSize = 500
            for chunkStart in stride(from: 0, to: lemmas.count, by: chunkSize) {
                let chunkEnd = min(chunkStart + chunkSize, lemmas.count)
                let chunk = lemmas[chunkStart..<chunkEnd]
                
                let placeholders = chunk.map { _ in "?" }.joined(separator: ",")
                let sql = """
                    SELECT root, translation FROM words
                    WHERE language = ?1 AND root IN (\(placeholders))
                    """
                
                var stmt: OpaquePointer?
                guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { continue }
                defer { sqlite3_finalize(stmt) }
                
                sqlite3_bind_text(stmt, 1, language.databaseCode, -1, SQLITE_TRANSIENT)
                for (i, lemma) in chunk.enumerated() {
                    sqlite3_bind_text(stmt, Int32(i + 2), lemma.lowercased(), -1, SQLITE_TRANSIENT)
                }
                
                while sqlite3_step(stmt) == SQLITE_ROW {
                    let root = String(cString: sqlite3_column_text(stmt, 0))
                    if sqlite3_column_type(stmt, 1) != SQLITE_NULL {
                        let translation = String(cString: sqlite3_column_text(stmt, 1))
                        result[root.lowercased()] = translation
                    }
                }
            }
            
            return result
        }
    }
    
    // MARK: - Helpers
    
    private func extractEntry(from stmt: OpaquePointer?, language: Language) -> LexiconEntry {
        let wordId = sqlite3_column_int64(stmt, 0)
        let lemma = String(cString: sqlite3_column_text(stmt, 1))
        let translation: String? = sqlite3_column_type(stmt, 2) != SQLITE_NULL
            ? String(cString: sqlite3_column_text(stmt, 2)) : nil
        let flagged = sqlite3_column_int(stmt, 3) != 0
        let isBaseVocab = sqlite3_column_int(stmt, 4) != 0
        return LexiconEntry(wordId: wordId, lemma: lemma, translation: translation,
                            language: language, isFlagged: flagged, isBaseVocab: isBaseVocab)
    }
    
    private func prepareStatements() {
        let formSQL = """
            SELECT w.id, w.root, w.translation, w.flagged, w.is_base_vocab
            FROM wordforms wf
            JOIN words w ON wf.word_id = w.id
            WHERE wf.form = ?1 AND w.language = ?2 AND wf.flagged = 0
            LIMIT 1
            """
        sqlite3_prepare_v2(db, formSQL, -1, &lookupByFormStmt, nil)
        
        let lemmaSQL = """
            SELECT id, root, translation, flagged, is_base_vocab
            FROM words
            WHERE root = ?1 AND language = ?2
            LIMIT 1
            """
        sqlite3_prepare_v2(db, lemmaSQL, -1, &lookupByLemmaStmt, nil)
        
        let translationSQL = """
            SELECT id, root, translation, is_base_vocab
            FROM words
            WHERE language = ?2 AND flagged = 0
              AND (translation = ?1 
                   OR translation LIKE ?1 || ',%'
                   OR translation LIKE '%, ' || ?1
                   OR translation LIKE '%, ' || ?1 || ',%')
            LIMIT 5
            """
        sqlite3_prepare_v2(db, translationSQL, -1, &lookupByTranslationStmt, nil)
        
        let searchSQL = """
            SELECT id, root, translation, flagged, is_base_vocab
            FROM words
            WHERE language = ?12 AND flagged = 0
              AND (
                root LIKE ?1 OR root LIKE ?2 OR root LIKE ?3 OR root LIKE ?4
                OR root LIKE ?5 OR root LIKE ?6 OR root LIKE ?7 OR root LIKE ?8
                OR root LIKE ?9
                OR translation LIKE ?10
                OR translation LIKE ?11
              )
            ORDER BY
                CASE WHEN root = ?13 THEN 0
                     WHEN root LIKE ?1 THEN 1
                     WHEN root LIKE ?2 OR root LIKE ?3 OR root LIKE ?4
                          OR root LIKE ?5 OR root LIKE ?6 OR root LIKE ?7
                          OR root LIKE ?8 OR root LIKE ?9 THEN 2
                     WHEN translation LIKE ?10 THEN 3
                     ELSE 4 END,
                is_base_vocab DESC,
                LENGTH(root) ASC
            LIMIT ?14
            """
        sqlite3_prepare_v2(db, searchSQL, -1, &searchStmt, nil)
    }
    
    private static let passthrough = PassthroughLexicon()
    
    private func passthroughResolution(observed: String, normalized: String, language: Language) -> WordResolution {
        Self.passthrough.resolve(observed: observed, normalized: normalized, language: language)
    }
    
    // MARK: - Cache
    
    private func cacheKey(_ form: String, language: Language) -> String {
        "\(language.rawValue)::\(form)"
    }
    
    private func getCached(_ form: String, language: Language) -> LexiconEntry? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return cache[cacheKey(form, language: language)]
    }
    
    private func setCache(_ form: String, language: Language, entry: LexiconEntry) {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if cache.count >= cacheLimit {
            let keysToRemove = Array(cache.keys.prefix(cacheLimit / 2))
            keysToRemove.forEach { cache.removeValue(forKey: $0) }
        }
        cache[cacheKey(form, language: language)] = entry
    }
    
    func clearCache() {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        cache.removeAll()
    }
}

// MARK: - Language Extension

extension Language {
    var databaseCode: String {
        switch self {
        case .english: return "en"
        case .spanish: return "es"
        case .french: return "fr"
        case .german: return "de"
        }
    }
    
    var usesDictionary: Bool {
        self != .english
    }
}

// MARK: - SQLITE_TRANSIENT Helper

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
