//
//  ContentView.swift
//  
//
//  Created by Ben Cerbin on 4/20/26.
//

import SwiftUI

struct ContentView: View {
    @State private var health = 70
    @State private var mood = "🙂"

    var body: some View {
        VStack(spacing: 30) {
            
            Text("Call Your Mom")
                .font(.largeTitle)
                .bold()
            
            Text(mood)
                .font(.system(size: 80))
            
            Text("Health: \(health)")
                .font(.title2)
            
            Button("📞 Call Loved One") {
                increaseHealth()
            }
            .padding()
            .background(Color.green)
            .foregroundColor(.white)
            .cornerRadius(10)
            
        }
        .onAppear {
            startHealthDecay()
        }
        .padding()
    }
    
    // MARK: - Logic
    
    func increaseHealth() {
        health = min(health + 15, 100)
        updateMood()
    }
    
    func decreaseHealth() {
        health = max(health - 5, 0)
        updateMood()
    }
    
    func updateMood() {
        if health > 70 {
            mood = "😄"
        } else if health > 30 {
            mood = "😐"
        } else {
            mood = "😢"
        }
    }
    
    func startHealthDecay() {
        Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
            decreaseHealth()
        }
    }
}
