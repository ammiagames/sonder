//
//  GoogleConfig.swift
//  sonder
//
//  Created by Michael Song on 2/4/26.
//

import Foundation
import GoogleSignIn

/// Configuration for Google Sign-In
struct GoogleConfig {
    // iOS Client ID (for the mobile app)
    static let clientID = "526758860188-epiiiih16mnelhjjv0a8uoef8s7g8unb.apps.googleusercontent.com"

    // Web Client ID (for Supabase server-side verification)
    static let serverClientID = "526758860188-l97ooc58s448uq1s4aj052j04ro9916c.apps.googleusercontent.com"

    /// Configure Google Sign-In SDK
    static func configure() {
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(
            clientID: clientID,
            serverClientID: serverClientID
        )
    }
}
