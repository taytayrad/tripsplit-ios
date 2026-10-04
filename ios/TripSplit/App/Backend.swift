import Foundation
import Supabase

/// Debug builds talk to the local Supabase on this Mac (`supabase start`); Release builds talk to the hosted
/// project. Publishable keys are meant to ship in apps; row-level security, not secrecy, protects the data.
enum Backend {
    #if DEBUG
    static let url = URL(string: "http://127.0.0.1:54321")!
    static let publishableKey = "sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH"  // the Supabase CLI's fixed local default
    #else
    static let url = URL(string: "https://ulnrarcdkvjiklacnnim.supabase.co")!
    static let publishableKey = "sb_publishable_5GGzAFrszourewMzP5Obpg_k8ETK0fc"
    #endif

    static let client = SupabaseClient(
        supabaseURL: url, supabaseKey: publishableKey,
        options: .init(auth: .init(emitLocalSessionAsInitialSession: true))
    )
}
