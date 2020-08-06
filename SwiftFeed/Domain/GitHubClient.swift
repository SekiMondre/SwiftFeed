//
//  GitHubSearch.swift
//  SwiftFeed
//
//  Created by André Vants Soares de Almeida on 04/08/20.
//

import Foundation

protocol SearchService {
    func getRepositories(
        matching query: String,
        sortBy sortingRule: SearchAPI.Sorting.Repository?,
        order: SearchAPI.Ordering?,
        page: Int,
        resultsPerPage: Int,
        completion: @escaping (Result<[Repository], Error>) -> Void
    ) -> Cancellable?
}

class GitHubClient: SearchService {
    
    let apiDomain: APIDomain
    
    private let session: URLSession
    
    private let rateLimitHandler: RateLimitHandler
    
    init(
        apiDomain: APIDomain = GitHubDomain.resolve(),
        session: URLSession = URLSession(configuration: .default),
        rateLimitHandler: RateLimitHandler = RateLimitHandler(rateLimit: SearchAPI.defaultRateLimit))
    {
        self.apiDomain = apiDomain
        self.session = session
        self.rateLimitHandler = rateLimitHandler
    }
    
    func getRepositories(
        matching query: String,
        sortBy sortingRule: SearchAPI.Sorting.Repository? = nil,
        order: SearchAPI.Ordering? = nil,
        page: Int = 1,
        resultsPerPage: Int = SearchAPI.defaultPageSize,
        completion: @escaping (Result<[Repository], Error>) -> Void
    ) -> Cancellable?
    {
        guard rateLimitHandler.holdRequestToken() else {
            defer { completion(.failure(NetworkError.rateLimitExceeded)) }
            return nil
        }
        let endpoint: SearchAPI.Endpoint = .repositories(
            matching: query,
            sort: sortingRule?.rawValue,
            order: order?.rawValue,
            pagination: Pagination(
                index: page,
                itemsPerPage: resultsPerPage))
        let request = Request(
            baseURL: apiDomain,
            endpoint: endpoint)
        
        return perform(request) { [weak self] (response: Response<SearchDTO<Repository>>) in
            self?.rateLimitHandler.consumeRequestToken()
            if let updatedRateLimits = RateLimitParser.parseRateLimitHeaders(from: response.httpHeaders) {
                print(updatedRateLimits)
                self?.rateLimitHandler.updateRateLimits(updatedRateLimits)
            }
            completion(response.result.map { $0.items })
        }
    }
    
    private func perform<T: Decodable>(_ request: URLRequestConvertible, completion: @escaping (Response<T>) -> Void) -> Cancellable? {
        do {
            let urlRequest = try request.asURLRequest()
            let dataTask = session.dataTask(with: urlRequest) { data, response, error in
                completion(Response(request: urlRequest, data: data, response: response, error: error))
            }
            dataTask.resume()
            return CancellableToken(task: dataTask)
        } catch {
            completion(Response(error: error))
            return nil
        }
    }
}
