//
//  SupabaseConfig.swift
//  sonder
//
//  Created by Michael Song on 2/4/26.
//

import Foundation
import Supabase

/// Configuration for Supabase client
struct SupabaseConfig {
    static let projectURL = URL(string: "https://qxpkyblruhyrokexihef.supabase.co")!
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InF4cGt5YmxydWh5cm9rZXhpaGVmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzAyNTc2NDcsImV4cCI6MjA4NTgzMzY0N30.v_YgYk8C8C9n_fcWZ9o6QVqGp-OmXpUn2ukzEZPmEA0"

    static let client = SupabaseClient(
        supabaseURL: projectURL,
        supabaseKey: anonKey
    )
}
