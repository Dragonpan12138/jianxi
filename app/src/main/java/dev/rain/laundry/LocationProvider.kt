package dev.rain.laundry

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Bundle
import android.os.Looper
import androidx.core.content.ContextCompat
import dev.rain.laundry.core.ClientError
import dev.rain.laundry.core.LocationFix
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withTimeoutOrNull
import kotlin.coroutines.resume

@Suppress("DEPRECATION")
class LocationProvider(private val context: Context) {
    fun permitted() = ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED
    suspend fun current(): LocationFix {
        if (!permitted()) throw ClientError("请允许本次定位后继续付款")
        val manager = context.getSystemService(LocationManager::class.java)
        val providers = listOf(LocationManager.NETWORK_PROVIDER, LocationManager.GPS_PROVIDER).filter { manager.isProviderEnabled(it) }
        if (providers.isEmpty()) throw ClientError("请先打开手机的位置服务")
        val last = providers.mapNotNull { provider ->
            try { manager.getLastKnownLocation(provider) } catch (_: SecurityException) { null }
        }
            .filter { System.currentTimeMillis() - it.time in 0..300_000 && it.accuracy <= 1500 }
            .maxByOrNull { it.time }
        if (last != null) return LocationFix(last.latitude, last.longitude)
        val fix = withTimeoutOrNull(20_000) {
            suspendCancellableCoroutine<Location> { continuation ->
                val listener = object : LocationListener {
                    override fun onLocationChanged(location: Location) {
                        if (continuation.isActive) { manager.removeUpdates(this); continuation.resume(location) }
                    }
                    override fun onProviderEnabled(provider: String) = Unit
                    override fun onProviderDisabled(provider: String) = Unit
                    override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) = Unit
                }
                continuation.invokeOnCancellation { manager.removeUpdates(listener) }
                providers.forEach { provider ->
                    try { manager.requestSingleUpdate(provider, listener, Looper.getMainLooper()) }
                    catch (_: SecurityException) { /* Approximate location can exclude GPS. */ }
                }
            }
        } ?: throw ClientError("暂时无法获取位置，请稍后重试")
        return LocationFix(fix.latitude, fix.longitude)
    }
}
