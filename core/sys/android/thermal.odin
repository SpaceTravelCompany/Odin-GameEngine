
package android

foreign import android "system:android"

/**
 * Thermal status used in function {@link AThermal_getCurrentThermalStatus} and
 * {@link AThermal_StatusCallback}.
 */
AThermalStatus :: enum {
    /** Error in thermal status. */
    ERROR = -1,
    /** Not under throttling. */
    NONE = 0,
    /** Light throttling where UX is not impacted. */
    LIGHT = 1,
    /** Moderate throttling where UX is not largely impacted. */
    MODERATE = 2,
    /** Severe throttling where UX is largely impacted. */
    SEVERE = 3,
    /** Platform has done everything to reduce power. */
    CRITICAL = 4,
    /**
     * Key components in platform are shutting down due to thermal condition.
     * Device functionalities will be limited.
     */
    EMERGENCY = 5,
    /** Need shutdown immediately. */
    SHUTDOWN = 6,
}

/**
 * An opaque type representing a handle to a thermal manager.
 * An instance of thermal manager must be acquired prior to
 * using thermal status APIs and must be released after use.
 *
 * <p>To use:<ul>
 *    <li>Create a new thermal manager instance by calling the
 *        {@link AThermal_acquireManager} function.</li>
 *    <li>Get current thermal status with
 *        {@link AThermal_getCurrentThermalStatus}.</li>
 *    <li>Register a thermal status listener with
 *        {@link AThermal_registerThermalStatusListener}.</li>
 *    <li>Unregister a thermal status listener with
 *        {@link AThermal_unregisterThermalStatusListener}.</li>
 *    <li>Release the thermal manager instance with
 *        {@link AThermal_releaseManager}.</li></ul></p>
 *
 */
AThermalManager :: struct{}

/**
 * This struct defines an instance of headroom threshold value and its status.
 * <p>
 * The value should be monotonically non-decreasing as the thermal status increases.
 * For {@link ATHERMAL_STATUS_SEVERE}, its headroom threshold is guaranteed to
 * be 1.0f. For status below severe status, the value should be lower or equal
 * to 1.0f, and for status above severe, the value should be larger or equal to 1.0f.
 * <p>
 * Also see {@link AThermal_getThermalHeadroom} for explanation on headroom, and
 * {@link AThermal_getThermalHeadroomThresholds} for how to use this.
 */
AThermalHeadroomThreshold :: struct {
	headroom: f32,
	thermalStatus: AThermalStatus,
}

/**
 * Prototype of the function that is called when thermal status changes.
 * It's passed the updated thermal status as parameter, as well as the
 * pointer provided by the client that registered a callback.
 */
AThermal_StatusCallback :: #type proc "c" (data: rawptr, status: AThermalStatus)

@(default_calling_convention="c")
foreign android {
	/**
	  * Acquire an instance of the thermal manager. This must be freed using
	  * {@link AThermal_releaseManager}.
	  *
	  * Available since API level 30.
	  *
	  * @return manager instance on success, nullptr on failure.
	  */
	AThermal_acquireManager :: proc() -> ^AThermalManager ---

	/**
	* Release the thermal manager pointer acquired via
	* {@link AThermal_acquireManager}.
	*
	* Available since API level 30.
	*
	* @param manager The manager to be released.
	*/
	AThermal_releaseManager :: proc(manager: ^AThermalManager) ---

	/**
	* Gets the current thermal status.
	*
	* Available since API level 30.
	*
	* @param manager The manager instance to use to query the thermal status.
	* Acquired via {@link AThermal_acquireManager}.
	*
	* @return current thermal status, ATHERMAL_STATUS_ERROR on failure.
	*/
	AThermal_getCurrentThermalStatus :: proc(manager: ^AThermalManager) -> AThermalStatus ---

	/**
	* Register the thermal status listener for thermal status change.
	*
	* Available since API level 30.
	*
	* @param manager The manager instance to use to register.
	* Acquired via {@link AThermal_acquireManager}.
	* @param callback The callback function to be called when thermal status updated.
	* @param data The data pointer to be passed when callback is called.
	*
	* @return 0 on success
	*         EINVAL if the listener and data pointer were previously added and not removed.
	*         EPERM if the required permission is not held.
	*         EPIPE if communication with the system service has failed.
	*/
	AThermal_registerThermalStatusListener :: proc(manager: ^AThermalManager, callback: AThermal_StatusCallback, data: rawptr) -> i32 ---

	/**
	* Unregister the thermal status listener previously resgistered.
	*
	* Available since API level 30.
	*
	* @param manager The manager instance to use to unregister.
	* Acquired via {@link AThermal_acquireManager}.
	* @param callback The callback function to be called when thermal status updated.
	* @param data The data pointer to be passed when callback is called.
	*
	* @return 0 on success
	*         EINVAL if the listener and data pointer were not previously added.
	*         EPERM if the required permission is not held.
	*         EPIPE if communication with the system service has failed.
	*/
	AThermal_unregisterThermalStatusListener :: proc(manager: ^AThermalManager, callback: AThermal_StatusCallback, data: rawptr) -> i32 ---

	/**
	* Provides an estimate of how much thermal headroom the device currently has before
	* hitting severe throttling.
	*
	* Note that this only attempts to track the headroom of slow-moving sensors, such as
	* the skin temperature sensor. This means that there is no benefit to calling this function
	* more frequently than about once per second, and attempted to call significantly
	* more frequently may result in the function returning {@code NaN}.
	*
	* In addition, in order to be able to provide an accurate forecast, the system does
	* not attempt to forecast until it has multiple temperature samples from which to
	* extrapolate. This should only take a few seconds from the time of the first call,
	* but during this time, no forecasting will occur, and the current headroom will be
	* returned regardless of the value of {@code forecastSeconds}.
	*
	* The value returned is a non-negative float that represents how much of the thermal envelope
	* is in use (or is forecasted to be in use). A value of 1.0 indicates that the device is
	* (or will be) throttled at {@link #ATHERMAL_STATUS_SEVERE}. Such throttling can affect the
	* CPU, GPU, and other subsystems. Values may exceed 1.0, but there is no implied mapping
	* to specific thermal levels beyond that point. This means that values greater than 1.0
	* may correspond to {@link #ATHERMAL_STATUS_SEVERE}, but may also represent heavier throttling.
	*
	* A value of 0.0 corresponds to a fixed distance from 1.0, but does not correspond to any
	* particular thermal status or temperature. Values on (0.0, 1.0] may be expected to scale
	* linearly with temperature, though temperature changes over time are typically not linear.
	* Negative values will be clamped to 0.0 before returning.
	*
	* Available since API level 31.
	*
	* @param manager The manager instance to use.
	*                Acquired via {@link AThermal_acquireManager}.
	* @param forecastSeconds how many seconds into the future to forecast. Given that device
	*                        conditions may change at any time, forecasts from further in the
	*                        future will likely be less accurate than forecasts in the near future.
	* @return a value greater than equal to 0.0, where 1.0 indicates the SEVERE throttling threshold,
	*         as described above. Returns NaN if the device does not support this functionality or
	*         if this function is called significantly faster than once per second.
	*/
	AThermal_getThermalHeadroom :: proc(manager: ^AThermalManager, forecastSeconds: i32) -> f32 ---

	/**
	 * Gets the thermal headroom thresholds for all available thermal status.
	 *
	 * A thermal status will only exist in output if the device manufacturer has the
	 * corresponding threshold defined for at least one of its slow-moving skin temperature
	 * sensors. If it's set, one should also expect to get it from
	 * {@link #AThermal_getCurrentThermalStatus} or {@link AThermal_StatusCallback}.
	 * <p>
	 * The headroom threshold is used to interpret the possible thermal throttling status based on
	 * the headroom prediction. For example, if the headroom threshold for
	 * {@link ATHERMAL_STATUS_LIGHT} is 0.7, and a headroom prediction in 10s returns 0.75
	 * (or `AThermal_getThermalHeadroom(10)=0.75`), one can expect that in 10 seconds the system
	 * could be in lightly throttled state if the workload remains the same. The app can consider
	 * taking actions according to the nearest throttling status the difference between the headroom and
	 * the threshold.
	 * <p>
	 * For new devices it's guaranteed to have a single sensor, but for older devices with multiple
	 * sensors reporting different threshold values, the minimum threshold is taken to be conservative
	 * on predictions. Thus, when reading real-time headroom, it's not guaranteed that a real-time value
	 * of 0.75 (or `AThermal_getThermalHeadroom(0)`=0.75) exceeding the threshold of 0.7 above
	 * will always come with lightly throttled state
	 * (or `AThermal_getCurrentThermalStatus()=ATHERMAL_STATUS_LIGHT`) but it can be lower
	 * (or `AThermal_getCurrentThermalStatus()=ATHERMAL_STATUS_NONE`).
	 * While it's always guaranteed that the device won't be throttled heavier than the unmet
	 * threshold's state, so a real-time headroom of 0.75 will never come with
	 * {@link #ATHERMAL_STATUS_MODERATE} but always lower, and 0.65 will never come with
	 * {@link ATHERMAL_STATUS_LIGHT} but {@link #ATHERMAL_STATUS_NONE}.
	 * <p>
	 * The returned list of thresholds is cached on first successful query and owned by the thermal
	 * manager, which will not change between calls to this function. The caller should only need to
	 * free the manager with {@link AThermal_releaseManager}.
	 *
	 * Available since API level 35.
	 *
	 * @param manager The manager instance to use.
	 *                Acquired via {@link AThermal_acquireManager}.
	 * @param outThresholds non-null output pointer to null AThermalHeadroomThreshold pointer, which
	 *                will be set to the cached array of thresholds if thermal thresholds are supported
	 *                by the system or device, otherwise nullptr or unmodified.
	 * @param size non-null output pointer whose value will be set to the size of the threshold array
	 *             or 0 if it's not supported.
	 * @return 0 on success
	 *         EINVAL if outThresholds or size_t is nullptr, or *outThresholds is not nullptr.
	 *         EPIPE if communication with the system service has failed.
	 *         ENOSYS if the feature is disabled by the current system.
	 */
	AThermal_getThermalHeadroomThresholds :: proc(manager: ^AThermalManager, outThresholds: ^^AThermalHeadroomThreshold, size: ^uint) -> i32 ---
}
