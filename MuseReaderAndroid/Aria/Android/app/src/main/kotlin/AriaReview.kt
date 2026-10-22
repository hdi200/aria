package aria.skip

import com.google.android.play.core.review.ReviewManagerFactory
import skip.ui.UIApplication

/// Google Play's in-app review, for the shared code's StoreKit requestReview (iOS).
/// Play decides whether the card actually shows, like the App Store does.
class AriaReview {
    fun request() {
        val activity = UIApplication.shared.androidActivity ?: return
        val manager = ReviewManagerFactory.create(activity)
        manager.requestReviewFlow().addOnCompleteListener { request ->
            if (request.isSuccessful) {
                manager.launchReviewFlow(activity, request.result)
            }
        }
    }
}
