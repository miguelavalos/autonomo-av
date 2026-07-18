import XCTest

@MainActor
final class GuestJourneyUITests: XCTestCase {
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.terminate()
        app.launch()
        addTeardownBlock { app.terminate() }
        return app
    }

    func testGuestOnboardingOffersSignInAndProInformation() {
        let app = launchApp()

        XCTAssertTrue(app.staticTexts["Business paperwork, ready for review"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Sign in"].isHittable)
        XCTAssertTrue(app.buttons["View Pro info"].isHittable)
    }

    func testSignInPanelExposesProvidersAndLegalConsent() {
        let app = launchApp()
        let signInButton = app.buttons["Sign in"]

        XCTAssertTrue(signInButton.waitForExistence(timeout: 10))
        signInButton.tap()

        XCTAssertTrue(app.buttons["autonomo.onboarding.auth.apple"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["autonomo.onboarding.auth.google"].exists)
        XCTAssertTrue(app.staticTexts["By continuing, you agree to the Terms and Privacy Policy."].exists)
    }

    func testGuestProSheetExposesSubscriptionAndLegalControls() {
        let app = launchApp()
        let proButton = app.buttons["View Pro info"]

        XCTAssertTrue(proButton.waitForExistence(timeout: 10))
        proButton.tap()

        XCTAssertTrue(app.staticTexts["Autonomo AV Pro"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["paywall.purchase"].exists)
        XCTAssertEqual(app.buttons["paywall.purchase"].label, "Sign in to start")
        XCTAssertTrue(app.staticTexts["Monthly Pro renews automatically. Manage or cancel anytime in App Store settings."].exists)
        XCTAssertTrue(app.buttons["paywall.redeemCode"].exists)
        XCTAssertEqual(
            app.buttons["paywall.terms"].exists,
            app.buttons["paywall.privacy"].exists,
            "Terms and Privacy must be configured as one legal-link pair."
        )
        XCTAssertTrue(app.buttons["Close"].exists)
    }
}
