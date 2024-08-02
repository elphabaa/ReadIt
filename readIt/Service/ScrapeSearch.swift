//
//  ScrapeSearch.swift
//  OpenArtemis
//
//  Created by Ethan Bills on 12/21/23.
//

import Foundation
import SwiftSoup

extension RedditScraper {
    static func search(query: String, searchType: String, sortBy: PostSortOption, topSortBy: TopPostListingSortOption,
                       over18: Bool? = false,
                       completion: @escaping (Result<[MixedMedia], Error>) -> Void) {
        // Construct the URL for the Reddit search based on the query
        var urlComponents = URLComponents(string: "\(baseRedditURL)/search")
        var queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "type", value: searchType)
        ]
        
        if searchType.isEmpty {
            // Only include these parameters if searchType is empty (post search)
            queryItems.append(URLQueryItem(name: "sort", value: sortBy.rawValue))
            queryItems.append(URLQueryItem(name: "t", value: topSortBy.rawValue))
        }
        
        // Add include_over_18=on if over18 is true
        if over18 == true {
            queryItems.append(URLQueryItem(name: "include_over_18", value: "on"))
        }
        
        urlComponents?.queryItems = queryItems
        
        guard let searchURL = urlComponents?.url else {
            completion(.failure(NSError(domain: "Invalid URL", code: 0, userInfo: nil)))
            return
        }
        
        // Create a URLSession and make a data task to fetch the HTML content
        var request = URLRequest(url: searchURL)
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        
        URLCache.shared = URLCache(memoryCapacity: 0, diskCapacity: 0, diskPath: nil)
        
        request.cachePolicy = .reloadIgnoringLocalCacheData
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let data = data else {
                completion(.failure(NSError(domain: "No data received", code: 0, userInfo: nil)))
                return
            }
            
            do {
                let htmlString = String(data: data, encoding: .utf8)!
                let doc = try SwiftSoup.parse(htmlString)
                
                var mixedMediaResults: [MixedMedia] = []
                
                if searchType == "sr" { // subreddit search
                    let subreddits = scrapeSubredditResults(data: doc)
                    mixedMediaResults.append(contentsOf: subreddits.map { MixedMedia.subreddit($0) })
                } else if searchType.isEmpty { // no filter is a post search
                    let posts = scrapePostResults(data: doc)
                    mixedMediaResults.append(contentsOf: posts.map { MixedMedia.post($0, date: nil) })
                }
                
                completion(.success(mixedMediaResults))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
    
    private static func scrapeSubredditResults(data: Document) -> [Subreddit] {
        do {
            // Select all elements with class "search-result-subreddit"
            let subredditElements = try data.select("div.search-result-subreddit")
            
            // Create an array to store the results
            var subreddits: [Subreddit] = []
            
            // Iterate over each subreddit element
            for subredditElement in subredditElements {
                // Extract the subreddit name from the "search-title" class
                let subredditName = try subredditElement.select("a.search-subreddit-link.may-blank").text().split(separator: "/").last.map { String($0) } ?? ""
                // Create a Subreddit object and add it to the array
                let subreddit = Subreddit(subreddit: subredditName)
                subreddits.append(subreddit)
            }
            
            return subreddits
        } catch {
            return []
        }
    }
    
    private static func scrapePostResults(data: Document) -> [Post] {
        let postElements = try? data.select("div.search-result-link")
        
        return postElements?.compactMap { postElement -> Post? in
            do {
                let id = try postElement.attr("data-fullname")
                let title = try postElement.select("a.search-title.may-blank").text()
                
                let subreddit = try postElement.select("a.search-subreddit-link.may-blank").text()
                let cleanedSubredditLink = subreddit.replacingOccurrences(of: "^(r/|/r/)", with: "", options: .regularExpression)
                
                let tagElement = try postElement.select("span.linkflairlabel").first()
                let tag = try tagElement?.text() ?? ""
                let author = try postElement.select("span.search-author a").text()
                let votes = try postElement.select("span.search-score").text()
                let time = try postElement.select("span.search-time time").attr("datetime")
                
                let commentsURL = try postElement.select("a.search-comments.may-blank").attr("href")
                let commentsCount = try postElement.select("a.search-comments.may-blank").text().split(separator: " ").first.map(String.init) ?? ""
                
                let footerElement = try postElement.select("div.search-result-footer").first()
                let mediaURL = try footerElement?.select("a.search-link.may-blank").attr("href") ?? commentsURL // bail to comments link (text post for example - which does not have a media url)
                
                let type = PostUtils.shared.determinePostType(mediaURL: mediaURL)
                
                var thumbnailURL: String? = nil
                
                if type == "video" || type == "gallery" || type == "article", let thumbnailElement = try? postElement.select("a.thumbnail img").first() {
                    thumbnailURL = try? thumbnailElement.attr("src").replacingOccurrences(of: "//", with: "https://")
                }
                
                return Post(id: id, subreddit: cleanedSubredditLink, title: title, tag: tag, author: author, votes: votes, time: time, mediaURL: mediaURL, commentsURL: commentsURL, commentsCount: commentsCount, type: type, thumbnailURL: thumbnailURL)
            } catch {
                // Handle any specific errors here if needed
                print("Error parsing post element: \(error)")
                return nil
            }
        } ?? []
    }
    
    static func scrapePostTitleAndAuthorFromURL(url: String, completion: @escaping (Result<(title: String, author: String), Error>) -> Void) {
            print("Starting to scrape URL: \(url)")
            if let cachedInfo = PostInfoCache.shared.getInfo(for: url) {
                completion(.success(cachedInfo))
                return
            }

            guard let url = URL(string: url) else {
                completion(.failure(NSError(domain: "RedditScraper", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
                return
            }

            var request = URLRequest(url: url)
            request.timeoutInterval = 30 // 30초로 타임아웃 설정
            request.addValue("YourApp/1.0", forHTTPHeaderField: "User-Agent")

            URLSession.shared.dataTask(with: request) { (data, response, error) in
                if let error = error {
                    completion(.failure(error))
                    return
                }

                guard let data = data else {
                    completion(.failure(NSError(domain: "RedditScraper", code: -2, userInfo: [NSLocalizedDescriptionKey: "No data received"])))
                    return
                }

                do {
                    let doc: Document = try SwiftSoup.parse(String(data: data, encoding: .utf8) ?? "")
                    let results = scrapePostTitleAndAuthorFromDocument(data: doc)
                    
                    if let firstResult = results.first {
                        completion(.success(firstResult))
                    } else {
                        completion(.failure(NSError(domain: "RedditScraper", code: -3, userInfo: [NSLocalizedDescriptionKey: "No results found"])))
                    }
                } catch {
                    completion(.failure(error))
                }
            }.resume()
        }

    private static func scrapePostTitleAndAuthorFromDocument(data: Document) -> [(author: String, title: String)] {
        do {
            // 포스트 제목 추출
            let title = try data.select("a.title").first()?.text() ?? ""
            
            // 포스트 작성자 추출
            let author = try data.select("a.author").first()?.text() ?? ""
            
            // 만약 제목이나 작성자를 찾지 못했다면, 페이지 제목에서 정보 추출 시도
            if title.isEmpty || author.isEmpty {
                let pageTitle = try data.title()
                let components = pageTitle.components(separatedBy: " 님께서 ")
                if components.count >= 2 {
                    let extractedAuthor = components[0]
                    let extractedTitle = components[1].components(separatedBy: "에 단 댓글")[0]
                    return [(author: extractedAuthor, title: extractedTitle)]
                }
            }
            
            // 제목과 작성자 모두 찾았다면 반환
            if !title.isEmpty && !author.isEmpty {
                return [(author: author, title: title)]
            }
            
            // 아무것도 찾지 못했다면 빈 배열 반환
            return []
        } catch {
            print("Error parsing document: \(error)")
            return []
        }
    }
}
