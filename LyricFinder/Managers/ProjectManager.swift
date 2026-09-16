import Foundation

/// Persists transcription projects as JSON in Documents/Projects.
/// Audio itself lives in Documents/Audio/ (see AudioImportManager).
@MainActor
final class ProjectManager: ObservableObject {
    @Published private(set) var projects: [TranscriptionProject] = []

    private var projectsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Projects", isDirectory: true)
    }

    init() {
        load()
    }

    // MARK: - CRUD

    func save(_ project: TranscriptionProject) {
        if let i = projects.firstIndex(where: { $0.id == project.id }) {
            var updated = project
            updated.updatedAt = Date()
            projects[i] = updated
        } else {
            projects.append(project)
        }
        persist(project: projects.first(where: { $0.id == project.id }) ?? project)
        sortProjects()
    }

    func delete(_ project: TranscriptionProject) {
        projects.removeAll { $0.id == project.id }
        try? FileManager.default.removeItem(at: fileURL(for: project.id))
        // Keep the audio file (other projects may share a name pattern);
        // storage cleanup is offered in Settings.
    }

    func delete(at offsets: IndexSet) {
        let victims = offsets.map { projects[$0] }
        victims.forEach(delete)
    }

    func project(id: UUID) -> TranscriptionProject? {
        projects.first(where: { $0.id == id })
    }

    func audioURL(for project: TranscriptionProject) -> URL {
        AudioImportManager.shared.urlForStoredFile(named: project.audioStoredFileName)
    }

    // MARK: - Persistence

    private func fileURL(for id: UUID) -> URL {
        projectsDirectory.appendingPathComponent("\(id.uuidString).json")
    }

    private func persist(project: TranscriptionProject) {
        do {
            try FileManager.default.createDirectory(at: projectsDirectory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(project)
            try data.write(to: fileURL(for: project.id), options: .atomic)
        } catch {
            print("[Projects] Save failed: \(error)")
        }
    }

    private func load() {
        do {
            try FileManager.default.createDirectory(at: projectsDirectory, withIntermediateDirectories: true)
            let files = try FileManager.default.contentsOfDirectory(at: projectsDirectory, includingPropertiesForKeys: nil)
            var loaded: [TranscriptionProject] = []
            for f in files where f.pathExtension == "json" {
                if let data = try? Data(contentsOf: f),
                   let p = try? JSONDecoder().decode(TranscriptionProject.self, from: data) {
                    loaded.append(p)
                }
            }
            projects = loaded.sorted(by: { $0.updatedAt > $1.updatedAt })
        } catch {
            print("[Projects] Load failed: \(error)")
            projects = []
        }
    }

    private func sortProjects() {
        projects.sort(by: { $0.updatedAt > $1.updatedAt })
    }
}
