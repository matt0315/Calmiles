import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var settings: SettingsStore
    @StateObject private var tripDetection = TripDetectionService.shared
    @State private var page = 0
    @State private var selectedCountry: CountryCode = .us

    var body: some View {
        TabView(selection: $page) {
            valuePropPage.tag(0)
            locationDisclosurePage.tag(1)
            countryPage.tag(2)
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .background(Color.calmilesBackground.ignoresSafeArea())
        .onAppear { AnalyticsStub.screen("onboarding") }
    }

    private var valuePropPage: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "road.lanes")
                .font(.system(size: 64))
                .foregroundStyle(CalmilesColor.copper)
                .accessibilityHidden(true)
            Text("Calmiles")
                .font(CalmilesTypography.largeTitle)
                .foregroundStyle(Color.calmilesPrimaryText)
            Text("Auto-detect trips, classify business or personal, and export accountant-ready CSV & PDF.")
                .font(CalmilesTypography.body)
                .foregroundStyle(Color.calmilesSecondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Text("For freelancers & sole traders in the US, AU, UK & CA.")
                .font(CalmilesTypography.callout)
                .foregroundStyle(Color.calmilesSecondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
            CalmilesPrimaryButton(title: "Continue") { withAnimation { page = 1 } }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
        }
    }

    private var locationDisclosurePage: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "location.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(CalmilesColor.copperSoft)
            Text("Location & battery")
                .font(CalmilesTypography.title)
                .foregroundStyle(Color.calmilesPrimaryText)
            Text("Calmiles uses background location to detect trips while you drive — even when the app is closed. This uses additional battery.\n\nYou can switch to manual logging anytime. Location stays on your device and iCloud (if enabled). We never sell your location.")
                .font(CalmilesTypography.body)
                .foregroundStyle(Color.calmilesSecondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            Spacer()
            CalmilesPrimaryButton(title: "Continue") {
                tripDetection.requestWhenInUse()
                tripDetection.start()
                withAnimation { page = 2 }
            }
            .padding(.horizontal, 24)
            CalmilesSecondaryButton(title: "Use Manual Only") {
                settings.settings.autoDetectEnabled = false
                withAnimation { page = 2 }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
    }

    private var countryPage: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("Where do you file?")
                .font(CalmilesTypography.title)
                .foregroundStyle(Color.calmilesPrimaryText)
            Text("We'll load IRS, ATO, HMRC, or CRA rate presets for estimates. Not tax advice.")
                .font(CalmilesTypography.body)
                .foregroundStyle(Color.calmilesSecondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            VStack(spacing: 10) {
                ForEach(CountryCode.allCases) { country in
                    Button {
                        selectedCountry = country
                    } label: {
                        HStack {
                            Text(country.displayName)
                                .foregroundStyle(Color.calmilesPrimaryText)
                            Spacer()
                            Text(country.authorityName)
                                .font(CalmilesTypography.caption)
                                .foregroundStyle(Color.calmilesSecondaryText)
                            if selectedCountry == country {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(CalmilesColor.copper)
                            }
                        }
                        .padding()
                        .background(Color.calmilesCard)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selectedCountry == country ? [.isSelected, .isButton] : .isButton)
                }
            }
            .padding(.horizontal, 24)
            Spacer()
            CalmilesPrimaryButton(title: "Get Started") {
                settings.completeOnboarding(country: selectedCountry)
                if settings.settings.autoDetectEnabled {
                    tripDetection.start()
                }
                AnalyticsStub.log("onboarding_complete", ["country": selectedCountry.rawValue])
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
    }
}
