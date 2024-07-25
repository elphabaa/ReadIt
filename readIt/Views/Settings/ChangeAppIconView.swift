//
//  ChangeAppIconView.swift
//  OpenArtemis
//
//  Created by daniel on 02/12/23.
//

import SwiftUI

struct ChangeAppIconView: View {
    var appIconManager = AppIconManager()
    let appTheme: AppThemeSettings
    let textSizePreference: TextSizePreference
    @State var currentAppicon: String = "Default"
    var body: some View {
        ThemedList(appTheme: appTheme, textSizePreference: textSizePreference) {
            ForEach(appIconManager.getIcons().sorted(), id: \.self){ icon in
                AppIconElement(icon: icon, textSizePreference: textSizePreference, currentAppIcon: $currentAppicon)
            }
        }
        .onAppear{
            currentAppicon = appIconManager.getCurrentIconName()
        }
    }
}

struct AppIconElement: View {
    let icon: String
    let textSizePreference: TextSizePreference
    @Binding var currentAppIcon: String //pass the icon as a Binding so we dont have to query the AppIcon Manager for ever alternate Icon
    @Environment(\.presentationMode) var presentationMode: Binding<PresentationMode>
    
    var body: some View {
        HStack{
            Image(uiImage: UIImage(named: icon)!)
                .resizable()
                .frame(width: 48, height: 48)
                .mask(RoundedRectangle(cornerSize: CGSize(width: 15, height: 15)))
            Text(icon.localizedCapitalized)
                .font(textSizePreference.title)
            Spacer()
            
            if currentAppIcon == icon {
                Image(systemName: "checkmark")
                    .foregroundColor(Color.artemisAccent)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            AppIconManager().setAppIcon(to: icon)
            currentAppIcon = icon
            self.presentationMode.wrappedValue.dismiss()
            
        }
    }
}
