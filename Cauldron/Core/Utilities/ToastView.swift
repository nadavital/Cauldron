//
//  ToastView.swift
//  Cauldron
//
//  Created by Nadav Avital on 10/21/25.
//

import SwiftUI

struct ToastView: View {
    let icon: String
    let message: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.orange)

            Text(message)
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .glassEffect(.regular, in: Capsule())
    }
}

struct ToastModifier: ViewModifier {
    @Binding var isShowing: Bool
    let icon: String
    let message: String
    let duration: TimeInterval
    @Namespace private var glassEffectNamespace

    func body(content: Content) -> some View {
        GlassEffectContainer(spacing: 40) {
            ZStack {
                content

                if isShowing {
                    VStack {
                        Spacer()

                        ToastView(icon: icon, message: message)
                            .glassEffectID("toast", in: glassEffectNamespace)
                            .glassEffectTransition(.materialize)
                            .padding(.bottom, 100)
                    }
                    .allowsHitTesting(false)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                            withAnimation {
                                isShowing = false
                            }
                        }
                    }
                }
            }
        }
    }
}

extension View {
    func toast(isShowing: Binding<Bool>, icon: String, message: String, duration: TimeInterval = 2.5) -> some View {
        self.modifier(ToastModifier(isShowing: isShowing, icon: icon, message: message, duration: duration))
    }
}

#Preview {
    VStack {
        Text("Content")
    }
    .toast(isShowing: .constant(true), icon: "cart.fill.badge.plus", message: "Added to grocery list")
}
