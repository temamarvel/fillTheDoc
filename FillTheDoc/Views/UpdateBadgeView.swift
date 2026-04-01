//
//  UpdateBadgeView.swift
//  FillTheDoc
//
//  Created by Артем Денисов on 01.04.2026.
//


import SwiftUI

struct UpdateBadgeView: View {
    let updateInfo: AppUpdateInfo
    @State private var isPopoverPresented = false

    var body: some View {
        Button {
            isPopoverPresented.toggle()
        } label: {
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(.yellow)
                .imageScale(.medium)
                .help("Доступна новая версия")
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPopoverPresented, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Доступно обновление")
                    .font(.headline)

                Text("Текущая версия: \(updateInfo.currentVersion)")
                Text("Новая версия: \(updateInfo.latestVersion)")
                    .fontWeight(.semibold)

                if let title = updateInfo.releaseTitle, !title.isEmpty {
                    Text(title)
                        .foregroundStyle(.secondary)
                }

                Divider()

                Link("Открыть релиз на GitHub", destination: updateInfo.releasePageURL)

                if let downloadURL = updateInfo.downloadURL {
                    Link("Скачать новую версию", destination: downloadURL)
                }
            }
            .padding(14)
            .frame(width: 280)
        }
    }
}

#Preview("UpdateBadgeView - basic") {
    HStack{
        Spacer()
        
        Text("1.3-beta")
            .font(.caption2)
            .foregroundStyle(.secondary)
        
        
        UpdateBadgeView(
            updateInfo: AppUpdateInfo(
                currentVersion: "1.3",
                latestVersion: "1.4",
                releasePageURL: URL(string: "https://github.com/example/repo/releases/tag/v1.4")!,
                downloadURL: URL(string: "https://github.com/example/repo/releases/download/v1.4/app.dmg"),
                releaseTitle: "Release 1.4",
                releaseNotes: "Bug fixes and performance improvements"
            )
        )
    }
    
    
    
    .padding(40)
    .frame(width: 300, height: 200)
}
