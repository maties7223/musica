import SwiftUI
import SwiftData
import AVFoundation

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var songs: [Song]
    @State private var recalculating = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 0) {
                        ForEach(ThemeChoice.allCases) { choice in
                            Button { ThemeStore.shared.select(choice) } label: {
                                swatch(choice)
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.vertical, 6)
                } header: {
                    Text("Color de la interfaz")
                } footer: {
                    Text("Cambia el color de botones, pestañas y portadas sin imagen.")
                }

                Section {
                    Button { Task { await recalculate() } } label: {
                        HStack {
                            Text("Recalcular duraciones")
                            Spacer()
                            if recalculating { ProgressView() }
                        }
                    }
                    .disabled(recalculating || songs.isEmpty)
                } header: {
                    Text("Biblioteca")
                } footer: {
                    Text("Vuelve a medir la duración real de cada canción por si alguna aparece con un tiempo distinto.")
                }
            }
            .navigationTitle("Ajustes")
            .miniPlayerInset()
        }
    }

    private func swatch(_ choice: ThemeChoice) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().fill(choice.gradient).frame(width: 46, height: 46)
                if ThemeStore.shared.choice == choice {
                    Image(systemName: "checkmark")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                }
            }
            Text(choice.name)
                .font(.caption)
                .foregroundStyle(.primary)
        }
    }

    @MainActor
    private func recalculate() async {
        recalculating = true
        var changed = 0
        for song in songs {
            let asset = LibraryManager.preciseAsset(song.url)
            guard let d = try? await asset.load(.duration),
                  d.seconds.isFinite, d.seconds > 0 else { continue }
            if abs(d.seconds - song.duration) > 0.5 {
                song.duration = d.seconds
                changed += 1
            }
        }
        try? context.save()
        recalculating = false
        if changed == 0 {
            Toast.shared.show("Las duraciones ya eran correctas", icon: "info.circle.fill")
        } else {
            Toast.shared.show("Duraciones corregidas: \(changed)")
        }
    }
}
