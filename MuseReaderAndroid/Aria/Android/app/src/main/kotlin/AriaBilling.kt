package aria.skip

import android.os.Handler
import android.os.Looper
import com.android.billingclient.api.AcknowledgePurchaseParams
import com.android.billingclient.api.BillingClient
import com.android.billingclient.api.BillingClientStateListener
import com.android.billingclient.api.BillingFlowParams
import com.android.billingclient.api.BillingResult
import com.android.billingclient.api.PendingPurchasesParams
import com.android.billingclient.api.ProductDetails
import com.android.billingclient.api.Purchase
import com.android.billingclient.api.QueryProductDetailsParams
import com.android.billingclient.api.QueryPurchasesParams
import java.util.concurrent.CompletableFuture
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference
import skip.ui.UIApplication

/// Blocking entry points are called by Swift off the main thread. Listener callbacks
/// never block: Play may deliver them on the UI thread, including after a pending payment.
object AriaBillingImpl {
    private const val PRODUCT = "com.hdi200.ariascore.unlimitedscores"
    @Volatile private var client: BillingClient? = null
    private data class PurchaseRequest(val productId: String, val outcome: CompletableFuture<String>)
    private val pendingPurchase = AtomicReference<PurchaseRequest?>()
    private val changed = AtomicBoolean(false)
    private val acknowledging = ConcurrentHashMap.newKeySet<String>()
    private val main = Handler(Looper.getMainLooper())

    private fun diagnostic(message: String) {
        // Never log purchase tokens, order IDs, accounts, or receipt JSON.
        if (BuildConfig.DEBUG) android.util.Log.d("AriaBilling", message)
    }

    @Synchronized
    private fun connectedClient(): BillingClient? {
        client?.let { if (it.isReady) return it else it.endConnection() }
        client = null
        val context = UIApplication.shared.androidActivity?.applicationContext ?: return null
        val newClient = BillingClient.newBuilder(context)
            .setListener { result, purchases -> purchasesUpdated(result, purchases) }
            .enablePendingPurchases(PendingPurchasesParams.newBuilder().enableOneTimeProducts().build())
            .enableAutoServiceReconnection()
            .build()
        val connected = CompletableFuture<Boolean>()
        client = newClient
        newClient.startConnection(object : BillingClientStateListener {
            override fun onBillingSetupFinished(result: BillingResult) {
                diagnostic("setup response=${result.responseCode}")
                connected.complete(result.responseCode == BillingClient.BillingResponseCode.OK)
            }
            override fun onBillingServiceDisconnected() { connected.complete(false) }
        })
        if (!wait(connected, false)) {
            newClient.endConnection()
            client = null
            return null
        }
        return newClient
    }

    // Query afresh: Google warns against stale ProductDetails when launching a flow.
    private fun details(productId: String): ProductDetails? {
        val billing = connectedClient() ?: return null
        val params = QueryProductDetailsParams.newBuilder().setProductList(listOf(
            QueryProductDetailsParams.Product.newBuilder().setProductId(productId)
                .setProductType(BillingClient.ProductType.INAPP).build()
        )).build()
        val found = CompletableFuture<ProductDetails?>()
        billing.queryProductDetailsAsync(params) { response, result ->
            diagnostic("product response=${response.responseCode} found=${result.productDetailsList.size}")
            found.complete(if (response.responseCode == BillingClient.BillingResponseCode.OK)
                result.productDetailsList.firstOrNull { it.productId == productId } else null)
        }
        return wait(found, null)
    }

    private fun buyOffer(details: ProductDetails): ProductDetails.OneTimePurchaseOfferDetails? =
        details.oneTimePurchaseOfferDetailsList?.firstOrNull { it.purchaseOptionId == "buy" }
            ?: details.oneTimePurchaseOfferDetails

    fun displayPrice(productId: String): String? =
        details(productId)?.let { buyOffer(it)?.formattedPrice }

    /// A successful empty query removes cached access after a revocation. An offline
    /// failure returns unavailable, preserving the owner's existing fail-open policy.
    fun ownership(productId: String): String {
        val billing = connectedClient() ?: return "unavailable"
        val answer = CompletableFuture<List<Purchase>?>()
        billing.queryPurchasesAsync(
            QueryPurchasesParams.newBuilder().setProductType(BillingClient.ProductType.INAPP).build()
        ) { result, purchases ->
            diagnostic("ownership response=${result.responseCode}")
            answer.complete(if (result.responseCode == BillingClient.BillingResponseCode.OK) purchases else null)
        }
        val purchases = wait(answer, null) ?: return "unavailable"
        val owned = purchases.filter { productId in it.products }
        val state = when {
            owned.any { it.purchaseState == Purchase.PurchaseState.PURCHASED } -> {
                owned.filter { it.purchaseState == Purchase.PurchaseState.PURCHASED }
                    .forEach { acknowledge(billing, it) }
                "purchased"
            }
            owned.any { it.purchaseState == Purchase.PurchaseState.PENDING } -> "pending"
            else -> "none"
        }
        diagnostic("ownership state=$state")
        return state
    }

    fun purchase(productId: String): String {
        val request = PurchaseRequest(productId, CompletableFuture())
        if (!pendingPurchase.compareAndSet(null, request)) return "failed:A purchase is already in progress."
        try {
            val billing = connectedClient() ?: return "failed:Google Play is not available."
            val details = details(productId) ?: return "failed:Aria Pro is temporarily unavailable. Please try again."
            val offer = buyOffer(details) ?: return "failed:Aria Pro has no available purchase option."
            val offerToken = offer.offerToken ?: return "failed:Aria Pro has no available purchase option."
            val activity = UIApplication.shared.androidActivity ?: return "failed:Aria is not in the foreground."
            val params = BillingFlowParams.newBuilder().setProductDetailsParamsList(listOf(
                BillingFlowParams.ProductDetailsParams.newBuilder().setProductDetails(details)
                    .setOfferToken(offerToken).build()
            )).build()
            val launch = CompletableFuture<BillingResult>()
            activity.runOnUiThread {
                try { launch.complete(billing.launchBillingFlow(activity, params)) }
                catch (error: Exception) { launch.completeExceptionally(error) }
            }
            val result = launch.get(30, TimeUnit.SECONDS)
            diagnostic("launch response=${result.responseCode}")
            if (result.responseCode == BillingClient.BillingResponseCode.ITEM_ALREADY_OWNED) return ownership(productId)
            if (result.responseCode != BillingClient.BillingResponseCode.OK) return failure(result)
            // Bound the wait if the activity or Play is killed without delivering a callback.
            return request.outcome.get(10, TimeUnit.MINUTES)
        } catch (error: Exception) {
            return "failed:Google Play did not complete the purchase. Check purchases before trying again."
        } finally {
            pendingPurchase.compareAndSet(request, null)
        }
    }

    private fun purchasesUpdated(result: BillingResult, purchases: List<Purchase>?) {
        diagnostic("update response=${result.responseCode}")
        // Process *all* relevant completed purchases, even without an open purchase sheet.
        if (result.responseCode == BillingClient.BillingResponseCode.OK) {
            purchases.orEmpty().filter { PRODUCT in it.products }.forEach { purchase ->
                if (purchase.purchaseState == Purchase.PurchaseState.PURCHASED) {
                    client?.let { acknowledge(it, purchase) }
                }
            }
            changed.set(true)
        }
        val request = pendingPurchase.get() ?: return
        val purchase = purchases.orEmpty().firstOrNull { request.productId in it.products }
        when (result.responseCode) {
            BillingClient.BillingResponseCode.OK -> when (purchase?.purchaseState) {
                Purchase.PurchaseState.PURCHASED -> request.outcome.complete("purchased")
                Purchase.PurchaseState.PENDING -> request.outcome.complete("pending")
                // An unrelated product callback must not complete this purchase.
                else -> if (purchases.isNullOrEmpty()) request.outcome.complete("failed:Google Play returned no purchase.")
            }
            BillingClient.BillingResponseCode.USER_CANCELED -> request.outcome.complete("cancelled")
            BillingClient.BillingResponseCode.ITEM_ALREADY_OWNED -> {
                changed.set(true)
                // Swift re-queries; this code never treats this response alone as entitlement.
                request.outcome.complete("purchased")
            }
            else -> request.outcome.complete(failure(result))
        }
    }

    private fun acknowledge(billing: BillingClient, purchase: Purchase, attempt: Int = 0) {
        if (purchase.purchaseState != Purchase.PurchaseState.PURCHASED || purchase.isAcknowledged) return
        if (!acknowledging.add(purchase.purchaseToken)) return
        val params = AcknowledgePurchaseParams.newBuilder().setPurchaseToken(purchase.purchaseToken).build()
        billing.acknowledgePurchase(params) { result ->
            acknowledging.remove(purchase.purchaseToken)
            diagnostic("acknowledge response=${result.responseCode} attempt=$attempt")
            if (result.responseCode != BillingClient.BillingResponseCode.OK && attempt < 5) {
                main.postDelayed({ acknowledge(billing, purchase, attempt + 1) }, 2000L shl attempt)
            }
            // Query on startup/resume retries after process death or longer offline periods.
        }
    }

    fun takePurchaseChange(): Boolean = changed.getAndSet(false)

    private fun failure(result: BillingResult): String =
        "failed:" + result.debugMessage.ifEmpty { "Google Play could not complete the purchase (${result.responseCode})." }

    private fun <T> wait(future: CompletableFuture<T>, fallback: T): T =
        try { future.get(30, TimeUnit.SECONDS) } catch (error: Exception) { fallback }
}

/// Swift's AnyDynamicObject reflects on instances, not Kotlin objects.
class AriaBilling {
    fun displayPrice(productId: String): String? = AriaBillingImpl.displayPrice(productId)
    fun ownership(productId: String): String = AriaBillingImpl.ownership(productId)
    fun purchase(productId: String): String = AriaBillingImpl.purchase(productId)
    fun takePurchaseChange(): Boolean = AriaBillingImpl.takePurchaseChange()
}
