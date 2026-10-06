import Foundation

struct User: Identifiable, Codable, Hashable {
    let id: UUID
    var displayName: String
}

struct School: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
}

struct SchoolClass: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
}

struct Subject: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
}

struct Teacher: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
}
