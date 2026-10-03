import Foundation

/// The hosted Supabase project. The publishable key is meant to ship in the app;
/// row-level security, not secrecy, protects the data.
/// ponytail: plain constants until Phase 2 adds supabase-swift and builds the client from them.
enum Backend {
    static let url = URL(string: "https://ulnrarcdkvjiklacnnim.supabase.co")!
    static let publishableKey = "sb_publishable_5GGzAFrszourewMzP5Obpg_k8ETK0fc"
}
