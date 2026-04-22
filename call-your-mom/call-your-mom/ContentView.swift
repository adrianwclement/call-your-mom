////
//  ContentView.swift
//
//  Created by Ben Cerbin on 4/20/26.
//


import SwiftUI

struct ContentView: View {
    @State private var health = 70

    var body: some View {
        VStack(spacing: 30) {
            
            Text("Call Your Mom")
                .font(.largeTitle)
                .bold()
            
            // Pet Image (based on health)
            Image(moodImage)
                .resizable()
                .scaledToFit()
                .frame(width: 200, height: 200)
                .scaleEffect(health > 70 ? 1.05 : 1.0)
                .animation(.easeInOut(duration: 0.3), value: health)
            
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
    
    // MARK: - Computed Mood Image
    
    var moodImage: String {
        if health > 70 {
            return "TamagotchiHappy"
        } else if health > 30 {
            return "TamagotchiFine"
        } else {
            return "TamagotchiSad"
        }
    }
    
    // MARK: - Logic
    
    func increaseHealth() {
        health = min(health + 15, 100)
    }
    
    func decreaseHealth() {
        health = max(health - 1, 0)
    }
    
    func startHealthDecay() {
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            decreaseHealth()
        }
    }
}
