import SwiftUI
import StoreKit

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var subscriptions: SubscriptionManager
    @State private var purchasingID: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(CalmilesColor.copper)
                        .accessibilityHidden(true)
                    Text("Calmiles Pro")
                        .font(CalmilesTypography.largeTitle)
                        .foregroundStyle(Color.calmilesPrimaryText)
                    Text("Unlimited auto-trips, full export history, and weekly insights — without the free-tier cap.")
                        .font(CalmilesTypography.body)
                        .foregroundStyle(Color.calmilesSecondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    VStack(alignment: .leading, spacing: 10) {
                        feature("Unlimited automatic trip detection")
                        feature("CSV & PDF export with rate estimates")
                        feature("Priority classification workflow")
                        feature("iCloud sync when available")
                    }
                    .padding(.horizontal)

                    if subscriptions.isLoading && subscriptions.products.isEmpty {
                        LoadingStateView(message: "Loading plans…")
                            .frame(height: 120)
                    } else if subscriptions.products.isEmpty {
                        // Fallback display when StoreKit config / ASC products unavailable
                        priceFallback
                    } else {
                        ForEach(subscriptions.products, id: \.id) { product in
                            productButton(product)
                        }
                    }

                    Button("Restore Purchases") {
                        Task { await subscriptions.restore() }
                    }
                    .font(CalmilesTypography.callout)
                    .foregroundStyle(CalmilesColor.copper)

                    Button("Manage Subscription") {
                        Task { await subscriptions.manageSubscriptions() }
                    }
                    .font(CalmilesTypography.callout)
                    .foregroundStyle(Color.calmilesSecondaryText)

                    Text("Subscriptions renew automatically unless cancelled at least 24 hours before the end of the period. Manage in Settings → Apple ID → Subscriptions.")
                        .font(CalmilesTypography.caption)
                        .foregroundStyle(Color.calmilesSecondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    if let err = subscriptions.lastError {
                        Text(err).font(CalmilesTypography.caption).foregroundStyle(CalmilesColor.danger)
                    }
                }
                .padding(.vertical, 24)
            }
            .background(Color.calmilesBackground.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task {
                await subscriptions.loadProducts()
                await subscriptions.refreshEntitlements()
                if subscriptions.isPro { dismiss() }
            }
            .onAppear { AnalyticsStub.screen("paywall") }
        }
    }

    private func feature(_ text: String) -> some View {
        Label(text, systemImage: "checkmark.circle.fill")
            .foregroundStyle(Color.calmilesPrimaryText)
            .font(CalmilesTypography.body)
            .symbolRenderingMode(.hierarchical)
            .labelStyle(.titleAndIcon)
    }

    private func productButton(_ product: Product) -> some View {
        Button {
            Task {
                purchasingID = product.id
                let ok = await subscriptions.purchase(product)
                purchasingID = nil
                if ok { dismiss() }
            }
        } label: {
            HStack {
                VStack(alignment: .leading) {
                    Text(product.displayName)
                        .font(CalmilesTypography.headline)
                    Text(product.description)
                        .font(CalmilesTypography.caption)
                        .foregroundStyle(CalmilesColor.mist.opacity(0.85))
                }
                Spacer()
                if purchasingID == product.id {
                    ProgressView().tint(CalmilesColor.mist)
                } else {
                    Text(product.displayPrice)
                        .font(CalmilesTypography.headline)
                }
            }
            .foregroundStyle(CalmilesColor.mist)
            .padding()
            .background(CalmilesColor.slateIndigo)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .padding(.horizontal)
        .disabled(purchasingID != nil)
        .accessibilityLabel("\(product.displayName), \(product.displayPrice)")
    }

    private var priceFallback: some View {
        VStack(spacing: 12) {
            CalmilesCard {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pro Monthly").font(CalmilesTypography.headline)
                    Text("$9.99 / month").foregroundStyle(Color.calmilesSecondaryText)
                    Text("Product ID: calmiles_pro_monthly").font(CalmilesTypography.caption)
                }
            }
            CalmilesCard {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pro Yearly").font(CalmilesTypography.headline)
                    Text("$59.99 / year").foregroundStyle(Color.calmilesSecondaryText)
                    Text("Product ID: calmiles_pro_yearly").font(CalmilesTypography.caption)
                }
            }
            Text("Connect a StoreKit Configuration or App Store products to purchase.")
                .font(CalmilesTypography.caption)
                .foregroundStyle(Color.calmilesSecondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding(.horizontal)
    }
}
