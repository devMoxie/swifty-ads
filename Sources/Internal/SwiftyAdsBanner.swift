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

enum SwiftyAdsBannerPositition {
    case top(ignoresSafeArea: Bool)
    case bottom(ignoresSafeArea: Bool)
}

protocol SwiftyAdsBannerType: AnyObject {
    func show(from viewController: UIViewController,
              at position: SwiftyAdsBannerPositition,
              isLandscape: Bool,
              animationDuration: TimeInterval,
              distanceAboveTabBar: CGFloat?,
              onOpen: (() -> Void)?,
              onClose: (() -> Void)?,
              onError: ((Error) -> Void)?)
    func remove()
    func updateSize(isLandscape: Bool)
}

final class SwiftyAdsBanner: NSObject {
    
    // MARK: - Properties
    
    private let adUnitId: String
    private let request: () -> GADRequest
    private var onOpen: (() -> Void)?
    private var onClose: (() -> Void)?
    private var onError: ((Error) -> Void)?
    
    private var bannerView: GADBannerView?
    private var position: SwiftyAdsBannerPositition = .bottom(ignoresSafeArea: false)
    private var animationDuration: TimeInterval = 1.4
    private var bannerViewConstraint: NSLayoutConstraint?
    private var animator: UIViewPropertyAnimator?
    private var currentView: UIView?
    private var visibleConstant: CGFloat = 0
    
    /// Creates some space between tab bar and ad to decrease an accidental touch on the ad
    private var distanceAboveTabBar: CGFloat = 0
    
    // MARK: - Computed Properties
    
    private var currentViewWidth: CGFloat {
        guard let currentView = currentView else { return 200 }
        switch position {
        case .top(let ignoresSafeArea), .bottom(let ignoresSafeArea):
            if ignoresSafeArea {
                return currentView.frame.size.width
            } else {
                return currentView.frame.inset(by: currentView.safeAreaInsets).size.width
            }
        }
    }
    
    // MARK: - Init
    
    init(adUnitId: String, request: @escaping () -> GADRequest) {
        self.adUnitId = adUnitId
        self.request = request
        super.init()
    }
}
 
// MARK: - SwiftyAdBannerType

extension SwiftyAdsBanner: SwiftyAdsBannerType {
    
    func show(from viewController: UIViewController,
              at position: SwiftyAdsBannerPositition,
              isLandscape: Bool,
              animationDuration: TimeInterval,
              distanceAboveTabBar: CGFloat?,
              onOpen: (() -> Void)?,
              onClose: (() -> Void)?,
              onError: ((Error) -> Void)?) {
        self.position = position
        self.animationDuration = animationDuration
        self.onOpen = onOpen
        self.onClose = onClose
        self.onError = onError
        self.distanceAboveTabBar = distanceAboveTabBar ?? 0
        
        // Remove old banners if needed
        remove()
        
        // Update current view reference
        currentView = viewController.view
        
        // Create new banner ad
        bannerView = GADBannerView()
        
        guard let bannerView = bannerView else {
            return
        }
         
        bannerView.adUnitID = adUnitId
        bannerView.delegate = self
        bannerView.rootViewController = viewController
        bannerView.translatesAutoresizingMaskIntoConstraints = false
        viewController.view.addSubview(bannerView)
         
        // Add constraints
        // We don't give the banner a width or height constraints, as the provided ad size will give the banner
        // an intrinsic content size
        let layoutGuide = viewController.view.safeAreaLayoutGuide
        switch position {
        case .top(let ignoresSafeArea):
            if ignoresSafeArea {
                bannerViewConstraint = bannerView.topAnchor.constraint(equalTo: viewController.view.topAnchor)
            } else {
                bannerViewConstraint = bannerView.topAnchor.constraint(equalTo: layoutGuide.topAnchor)
            }
        case .bottom(let ignoresSafeArea):
            if ignoresSafeArea {
                bannerViewConstraint = bannerView.bottomAnchor.constraint(equalTo: viewController.view.bottomAnchor)
            } else {
                
                // Handle UITabBarController
                if let tabBarController = viewController as? UITabBarController {
                    let tabController = tabBarController.viewControllers!.first!
                    let tabBarHeight = tabController.view.safeAreaInsets.bottom
                    visibleConstant = -tabBarHeight + -self.distanceAboveTabBar
                    bannerViewConstraint = bannerView.bottomAnchor.constraint(equalTo: viewController.view.bottomAnchor, constant: 0)
                    
                    // This is needed so that the bannerView animation occurs behind the the tab bar.
                    viewController.view.bringSubviewToFront(tabBarController.tabBar)
                } else {
                    bannerViewConstraint = bannerView.bottomAnchor.constraint(equalTo: layoutGuide.bottomAnchor)
                }
            }
        }
         
        NSLayoutConstraint.activate([
            bannerView.centerXAnchor.constraint(equalTo: layoutGuide.centerXAnchor),
            bannerViewConstraint!
        ])
        
        // Update the adaptive banner size
        updateSize(isLandscape: isLandscape)
        
        // Create an ad request and load the adaptive banner ad.
        bannerView.load(request())
        
        // Move banner off screen
        animateToOffScreenPosition(bannerView, from: viewController, position: position, animated: false)
    }
    
    func remove() {
        guard bannerView != nil else {
            return
        }
        
        bannerView?.delegate = nil
        bannerView?.removeFromSuperview()
        bannerView = nil
        bannerViewConstraint = nil
        currentView = nil
        onClose?()
    }
    
    func updateSize(isLandscape: Bool) {
        if isLandscape {
            bannerView?.adSize = GADLandscapeAnchoredAdaptiveBannerAdSizeWithWidth(currentViewWidth)
        } else {
            bannerView?.adSize = GADPortraitAnchoredAdaptiveBannerAdSizeWithWidth(currentViewWidth)
        }
    }
}

// MARK: - GADBannerViewDelegate

extension SwiftyAdsBanner: GADBannerViewDelegate {
    
    func adViewDidReceiveAd(_ bannerView: GADBannerView) {
        print("SwiftyAdsBanner did receive ad from: \(bannerView.responseInfo?.adNetworkClassName ?? "")")
        animateToOnScreenPosition(bannerView, from: bannerView.rootViewController)
    }

    func adView(_ bannerView: GADBannerView, didFailToReceiveAdWithError error: GADRequestError) {
        animateToOffScreenPosition(bannerView, from: bannerView.rootViewController, position: position)
        onError?(error)
    }
}

// MARK: - Private Methods

private extension SwiftyAdsBanner {
    
    func animateToOnScreenPosition(_ bannerAd: GADBannerView,
                                   from viewController: UIViewController?,
                                   completion: (() -> Void)? = nil) {
        // We can only animate the banner to its on-screen position with a valid view controller
        guard let viewController = viewController else {
            return
        }
        
        // We can only animate the banner to its on-screen position if its not already visible
        guard let bannerViewConstraint = bannerViewConstraint, bannerViewConstraint.constant != visibleConstant else {
            return
        }
        
        // Animate banner
        bannerAd.isHidden = false
        bannerViewConstraint.constant = visibleConstant
        
        stopCurrentAnimatorAnimations()
        animator = UIViewPropertyAnimator(duration: animationDuration, curve: .easeOut) {
            viewController.view.layoutIfNeeded()
        }
        
        animator?.addCompletion { [weak self] _ in
            guard let self = self else { return }
            self.onOpen?()
            completion?()
        }

        animator?.startAnimation()
    }
    
    func animateToOffScreenPosition(_ bannerAd: GADBannerView,
                                    from viewController: UIViewController?,
                                    position: SwiftyAdsBannerPositition,
                                    animated: Bool = true,
                                    completion: (() -> Void)? = nil) {
        // We can only animate the banner to its off-screen position with a valid view controller
        guard let viewController = viewController else {
            return
        }
        
        // We can only animate the banner to its off-screen position if its already visible
        guard let bannerViewConstraint = bannerViewConstraint, bannerViewConstraint.constant == visibleConstant else {
            return
        }
        
        // Get banner off-screen constant
        let newConstant: CGFloat
        switch position {
        case .top:
            newConstant = 0 - (bannerAd.adSize.size.height * 3) // *3 due to iPhoneX safe area
        case .bottom:
            newConstant = 0 + (bannerAd.adSize.size.height * 3) // *3 due to iPhoneX safe area
        }

        // Only animate the banner if we want it animated
        guard animated else {
            bannerAd.isHidden = true
            bannerViewConstraint.constant = newConstant
            return
        }
        
        // Animate banner
        bannerViewConstraint.constant = newConstant
        stopCurrentAnimatorAnimations()
        animator = UIViewPropertyAnimator(duration: animationDuration, curve: .easeOut) {
            viewController.view.layoutIfNeeded()
        }
        
        animator?.addCompletion { [weak self] _ in
            guard let self = self else { return }
            bannerAd.isHidden = true
            self.onClose?()
            completion?()
        }
        
        animator?.startAnimation()
    }

    func stopCurrentAnimatorAnimations() {
        animator?.stopAnimation(false)
        animator?.finishAnimation(at: .current)
    }
}
