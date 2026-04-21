//
//  MainTabView.swift
//  call-your-mom
//
//  Created by Ben Cerbin on 4/21/26.
//

import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            
            DashboardView()
                .tabItem {
                    Image(systemName: "heart.fill")
                    Text("Tamagotchi")
                }
            
            ContactsView()
                .tabItem {
                    Image(systemName: "person.2.fill")
                    Text("Contacts")
                }
            
            HistoryView()
                .tabItem {
                    Image(systemName: "clock.fill")
                    Text("History")
                }
            
            AccountView()
                .tabItem {
                    Image(systemName: "gearshape.fill")
                    Text("Account")
                }
        }
    }
}
