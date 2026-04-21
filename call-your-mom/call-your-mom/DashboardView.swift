//
//  DashboardView.swift
//  call-your-mom
//
//  Created by Ben Cerbin on 4/21/26.
//

import SwiftUI

struct DashboardView: View {
    
    @State private var health: Double = 70
    @State private var streak: Int = 3
    @State private var callsToday: Int = 1
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    
                    HeaderView()
                    
                    TamagotchiView(health: health)
                    
                    HealthCard(health: health)
                    
                    StatsRow(streak: streak, callsToday: callsToday)
                    
                    ActionButtons(health: $health)
                    
                }
                .padding()
            }
            .navigationTitle("Dashboard")
        }
        .onAppear{
               startHealthDecay()
       }
    }
    
    func decreaseHealth() {
        health = max(health - 5, 0)
    }
    
    func startHealthDecay() {
        Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
            decreaseHealth()
        }
    }
}

struct HeaderView: View {
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Welcome Back 👋")
                    .font(.title2)
                    .fontWeight(.medium)
                
                Text("Keep your Tamagotchi alive!")
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            Image(systemName: "person.circle.fill")
                .font(.largeTitle)
                .foregroundColor(.blue)
        }
    }
}

struct TamagotchiView: View {
    var health: Double
    
    var body: some View {
        VStack(spacing: 30) {
            
            
            Image(moodImage)
                .resizable()
                .scaledToFit()
                .frame(width: 200, height: 200)
                .scaleEffect(health > 70 ? 1.05 : 1.0)
                .animation(.easeInOut(duration: 0.3), value: health)
                
        }
    }
    
    var moodImage: String {
        if health > 70 {
            return "TamagotchiHappy"
        } else if health > 30 {
            return "TamagotchiFine"
        } else {
            return "TamagotchiSad"
        }
    }
}

struct HealthCard: View {
    var health: Double
    
    var body: some View {
        VStack(spacing: 15) {
            
            Text("Health")
                .font(.headline)
            
            ProgressView(value: health, total: 100)
                .progressViewStyle(LinearProgressViewStyle())
            
            Text("\(Int(health))%")
                .font(.title)
                .fontWeight(.bold)
            
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.systemGray6))
        .cornerRadius(16)
    }
}

struct StatsRow: View {
    var streak: Int
    var callsToday: Int
    
    var body: some View {
        HStack(spacing: 15) {
            
            StatCard(title: "🔥 Streak", value: "\(streak)")
            StatCard(title: "📞 Calls", value: "\(callsToday)")
            
        }
    }
}

struct StatCard: View {
    var title: String
    var value: String
    
    var body: some View {
        VStack {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.gray)
            
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct ActionButtons: View {
    @Binding var health: Double
    
    var body: some View {
        VStack(spacing: 15) {
            
            Button(action: {
                health = min(health + 10, 100)
            }) {
                Text("📞 Call Someone")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            
            Button(action: {
                print("View history")
            }) {
                Text("📜 View Call History")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
        }
    }
}
