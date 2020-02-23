//    The MIT License (MIT)
//
//    Copyright (c) 2015-2020 Dominik Ringler
//
//    Permission is hereby granted, free of charge, to any person obtaining a copy
//    of this software and associated documentation files (the "Software"), to deal
//    in the Software without restriction, including without limitation the rights
//    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//    copies of the Software, and to permit persons to whom the Software is
//    furnished to do so, subject to the following conditions:
//
//    The above copyright notice and this permission notice shall be included in all
//    copies or substantial portions of the Software.
//
//    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//    SOFTWARE.

import GoogleMobileAds

/// SwiftyAdsDelegate
public protocol SwiftyAdsDelegate: class {
    /// SwiftyAds did open
    func swiftyAdsDidOpen(_ swiftyAds: SwiftyAds)
    /// SwiftyAds did close
    func swiftyAdsDidClose(_ swiftyAds: SwiftyAds)
    /// SwiftyAds did change consent status
    func swiftyAds(_ swiftyAds: SwiftyAds, didChange consentStatus: SwiftyAdsConsentStatus)
    /// SwiftyAds did reward user
    func swiftyAds(_ swiftyAds: SwiftyAds, didRewardUserWithAmount rewardAmount: Int)
}

/// A protocol for mediation implementations
public protocol SwiftyAdsMediationType: class {
    func update(for consentType: SwiftyAdsConsentStatus)
}

/// SwiftyAds mode
public enum SwiftyAdsMode {
    case production
    case test(devices: [String])
}

/// SwiftyAds type
public protocol SwiftyAdsType: AnyObject {
    var hasConsent: Bool { get }
    var isRequiredToAskForConsent: Bool { get }
    var isInterstitialReady: Bool { get }
    var isRewardedVideoReady: Bool { get }
    func setup(with viewController: UIViewController,
               delegate: SwiftyAdsDelegate?,
               mediation: SwiftyAdsMediationType?,
               bannerAnimationDuration: TimeInterval,
               mode: SwiftyAdsMode,
               handler: @escaping (_ hasConsent: Bool) -> Void)
    func askForConsent(from viewController: UIViewController)
    func showBanner(from viewController: UIViewController, isAtTop: Bool)
    func showInterstitial(from viewController: UIViewController, withInterval interval: Int?)
    func showRewardedVideo(from viewController: UIViewController)
    func removeBanner()
    func disable()
}

/**
 SwiftyAds
 
 A singleton class to manage adverts from Google AdMob.
 */
public final class SwiftyAds: NSObject {
    
    // MARK: - Static Properties
    
    /// The shared instance of SwiftyAds using default non costumizable settings
    public static let shared = SwiftyAds()
    
    // MARK: - Properties
    
    /// Ads
    private lazy var banner: SwiftyAdsBannerType = {
        let ad = SwiftyAdsBanner(
            adUnitId: configuration.bannerAdUnitId,
            notificationCenter: .default,
            isLandscape: { UIDevice.current.orientation.isLandscape },
            request: ({ [unowned self] in
                self.makeRequest()
            }),
            didOpen: ({ [weak self] in
                guard let self = self else { return }
                self.delegate?.swiftyAdsDidOpen(self)
            }),
            didClose: ({ [weak self] in
                guard let self = self else { return }
                self.delegate?.swiftyAdsDidClose(self)
            })
        )
        return ad
    }()
    
    private lazy var interstitial: SwiftyAdsInterstitialType = {
        let ad = SwiftyAdsInterstitial(
            adUnitId: configuration.interstitialAdUnitId,
            request: ({ [unowned self] in
                self.makeRequest()
            }),
            didOpen: ({ [weak self] in
                guard let self = self else { return }
                self.delegate?.swiftyAdsDidOpen(self)
            }),
            didClose: ({ [weak self] in
                guard let self = self else { return }
                self.delegate?.swiftyAdsDidClose(self)
            })
        )
        return ad
    }()
    
    private lazy var rewarded: SwiftyAdsRewardedType = {
        let ad = SwiftyAdsRewarded(
            adUnitId: configuration.rewardedVideoAdUnitId,
            request: ({ [unowned self] in
                self.makeRequest()
            }),
            didOpen: ({ [weak self] in
                guard let self = self else { return }
                self.delegate?.swiftyAdsDidOpen(self)
            }),
            didClose: ({ [weak self] in
                guard let self = self else { return }
                self.delegate?.swiftyAdsDidClose(self)
            }),
            didReward: ({ [weak self] rewardAmount in
                guard let self = self else { return }
                self.delegate?.swiftyAds(self, didRewardUserWithAmount: rewardAmount)
            })
        )
        return ad
    }()
    
    /// Init
    private var configuration: SwiftyAdsConfiguration
    private let requestBuilder: SwiftyAdsRequestBuilderType
    private let intervalTracker: SwiftyAdsIntervalTrackerType
    private let consentManager: SwiftyAdsConsentManagerType
    private var mediation: SwiftyAdsMediationType?
    private weak var delegate: SwiftyAdsDelegate?
    private var isRemoved = false
    private var mode: SwiftyAdsMode
    private var testDevices: [Any] = [kGADSimulatorID]
    
    // MARK: - Init
    
    override convenience init() {
        let configuration: SwiftyAdsConfiguration = .debug
        
        let consentManager = SwiftyAdsConsentManager(
            ids: configuration.ids,
            configuration: configuration.gdpr
        )
        
        let requestBuilder = SwiftyAdsRequestBuilder(
            mobileAds: .sharedInstance(),
            isGDPRRequired: consentManager.isInEEA,
            isNonPersonalizedOnly: consentManager.status == .nonPersonalized,
            isTaggedForUnderAgeOfConsent: consentManager.isTaggedForUnderAgeOfConsent
        )
        
        self.init(
            configuration: configuration,
            requestBuilder: requestBuilder,
            intervalTracker: SwiftyAdsIntervalTracker(),
            mediation: nil,
            consentManager: consentManager,
            mode: .production,
            notificationCenter: .default
        )
    }
    
    init(configuration: SwiftyAdsConfiguration,
         requestBuilder: SwiftyAdsRequestBuilderType,
         intervalTracker: SwiftyAdsIntervalTrackerType,
         mediation: SwiftyAdsMediationType?,
         consentManager: SwiftyAdsConsentManagerType,
         mode: SwiftyAdsMode,
         notificationCenter: NotificationCenter) {
        self.configuration = configuration
        self.requestBuilder = requestBuilder
        self.intervalTracker = intervalTracker
        self.mediation = mediation
        self.consentManager = consentManager
        self.mode = mode
        super.init()
        print("AdMob SDK version \(GADRequest.sdkVersion())")
    }
}

// MARK: - SwiftyAdType

extension SwiftyAds: SwiftyAdsType {
    
    /// Check if user has consent e.g to hide rewarded video button
    public var hasConsent: Bool {
        consentManager.hasConsent
    }
     
    /// Check if we must ask for consent e.g to hide change consent button in apps settings menu (required GDPR requirement)
    public var isRequiredToAskForConsent: Bool {
        consentManager.isRequiredToAskForConsent
    }
     
    /// Check if interstitial video is ready (e.g to show alternative ad like an in house ad)
    /// Will try to reload an ad if it returns false.
    public var isInterstitialReady: Bool {
        interstitial.isReady
    }
     
    /// Check if reward video is ready (e.g to hide a reward video button)
    /// Will try to reload an ad if it returns false.
    public var isRewardedVideoReady: Bool {
        rewarded.isReady
    }
    
    /// Setup swift ad
    ///
    /// - parameter viewController: The view controller that will present the consent alert if needed.
    /// - parameter delegate: A delegate to receive event callbacks. Can also be set manually if needed.
    /// - parameter mediation: A implementation of SwiftyAdsMediationType protocol to manage mediation support.
    /// - parameter bannerAnimationDuration: The duration of the banner animation.
    /// - parameter mode: Set the mode of ads, production or debug.
    /// - returns handler: A handler that will return a boolean with the consent status.
    public func setup(with viewController: UIViewController,
                      delegate: SwiftyAdsDelegate?,
                      mediation: SwiftyAdsMediationType?,
                      bannerAnimationDuration: TimeInterval,
                      mode: SwiftyAdsMode,
                      handler: @escaping (_ hasConsent: Bool) -> Void) {
        self.delegate = delegate
        self.mediation = mediation
        
        switch mode {
        case .production:
            configuration = .propertyList
        case .test(let testDevices):
            configuration = .debug
            self.testDevices.append(contentsOf: testDevices)
        }
        
        // Update banner animation duration
        banner.updateAnimationDuration(to: bannerAnimationDuration)
       
        // Make consent request
        self.consentManager.ask(from: viewController, skipIfAlreadyAuthorized: true) { status in
            self.handleConsentStatusChange(status)
           
            switch status {
            case .personalized, .nonPersonalized:
                if !self.isRemoved {
                    self.interstitial.load()
                }
                self.rewarded.load()
                handler(true)
            
            case .adFree, .unknown:
                handler(false)
            }
        }
    }

    /// Ask for consent. Use this for the consent button that should be e.g in settings.
    ///
    /// - parameter viewController: The view controller that will present the consent form.
    public func askForConsent(from viewController: UIViewController) {
        consentManager.ask(from: viewController, skipIfAlreadyAuthorized: false) { status in
            self.handleConsentStatusChange(status)
        }
    }
    
    /// Show banner ad
    ///
    /// - parameter viewController: The view controller that will present the ad.
    /// - parameter isAtTop: If set to true the banner will be displayed at the top.
    public func showBanner(from viewController: UIViewController, isAtTop: Bool) {
        guard !isRemoved, hasConsent else { return }
        banner.show(from: viewController, at: isAtTop ? .top : .bottom)
    }
    
    /// Show interstitial ad
    ///
    /// - parameter viewController: The view controller that will present the ad.
    /// - parameter interval: The interval of when to show the ad, e.g every 4th time the method is called. Set to nil to always show.
    public func showInterstitial(from viewController: UIViewController, withInterval interval: Int?) {
        guard !isRemoved, hasConsent else { return }
        guard intervalTracker.canShow(forInterval: interval) else { return }
        guard isInterstitialReady else { return }
        interstitial.show(for: viewController)
    }
    
    /// Show rewarded video ad
    ///
    /// - parameter viewController: The view controller that will present the ad.
    public func showRewardedVideo(from viewController: UIViewController) {
        guard hasConsent else { return }
        rewarded.show(from: viewController)
    }
    
    /// Remove banner ads
    public func removeBanner() {
        banner.remove()
    }

    /// Disable ads e.g in app purchases
    public func disable() {
        isRemoved = true
        removeBanner()
        interstitial.stopLoading()
    }
}

// MARK: - Private Methods

private extension SwiftyAds {
    
    func handleConsentStatusChange(_ status: SwiftyAdsConsentStatus) {
        delegate?.swiftyAds(self, didChange: status)
        mediation?.update(for: status)
    }
    
    func makeRequest() -> GADRequest {
        switch mode {
        case .production:
            return requestBuilder.build(.production)
        case .test(let devices):
            return requestBuilder.build(.test(devices: devices))
        }
    }
}
