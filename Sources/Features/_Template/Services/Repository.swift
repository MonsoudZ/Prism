import Foundation
protocol Repository { func all() async throws -> [Entity] }
struct DefaultRepository: Repository {
    func all() async throws -> [Entity] { [Entity(id: UUID())] }
}
