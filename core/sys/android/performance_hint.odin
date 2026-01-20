
package android

foreign import android "system:android"

/**
 * An opaque type representing a handle to a performance hint manager.
 * It must be released after use.
 *
 * <p>To use:<ul>
 *    <li>Obtain the performance hint manager instance by calling
 *        {@link APerformanceHint_getManager} function.</li>
 *    <li>Create an {@link APerformanceHintSession} with
 *        {@link APerformanceHint_createSession}.</li>
 *    <li>Get the preferred update rate in nanoseconds with
 *        {@link APerformanceHint_getPreferredUpdateRateNanos}.</li>
 */
APerformanceHintManager :: struct{}

/**
 * An opaque type representing a handle to a performance hint session.
 * A session can only be acquired from a {@link APerformanceHintManager}
 * with {@link APerformanceHint_getPreferredUpdateRateNanos}. It must be
 * freed with {@link APerformanceHint_closeSession} after use.
 *
 * A Session represents a group of threads with an inter-related workload such that hints for
 * their performance should be considered as a unit. The threads in a given session should be
 * long-life and not created or destroyed dynamically.
 *
 * <p>Each session is expected to have a periodic workload with a target duration for each
 * cycle. The cycle duration is likely greater than the target work duration to allow other
 * parts of the pipeline to run within the available budget. For example, a renderer thread may
 * work at 60hz in order to produce frames at the display's frame but have a target work
 * duration of only 6ms.</p>
 *
 * <p>After each cycle of work, the client is expected to use
 * {@link APerformanceHint_reportActualWorkDuration} to report the actual time taken to
 * complete.</p>
 *
 * <p>To use:<ul>
 *    <li>Update a sessions target duration for each cycle of work
 *        with  {@link APerformanceHint_updateTargetWorkDuration}.</li>
 *    <li>Report the actual duration for the last cycle of work with
 *        {@link APerformanceHint_reportActualWorkDuration}.</li>
 *    <li>Release the session instance with
 *        {@link APerformanceHint_closeSession}.</li></ul></p>
 */
APerformanceHintSession :: struct{}

/**
 * {@link AWorkDuration} is an opaque type that represents the breakdown of the
 * actual workload duration in each component internally.
 *
 * A new {@link AWorkDuration} can be obtained using
 * {@link AWorkDuration_create()}, when the client finishes using
 * {@link AWorkDuration}, {@link AWorkDuration_release()} must be
 * called to destroy and free up the resources associated with
 * {@link AWorkDuration}.
 *
 * This file provides a set of functions to allow clients to set the measured
 * work duration of each component on {@link AWorkDuration}.
 *
 * - AWorkDuration_setWorkPeriodStartTimestampNanos()
 * - AWorkDuration_setActualTotalDurationNanos()
 * - AWorkDuration_setActualCpuDurationNanos()
 * - AWorkDuration_setActualGpuDurationNanos()
 */
AWorkDuration :: struct{}

@(default_calling_convention="c")
foreign android {
	/**
	  * Acquire an instance of the performance hint manager.
	  *
	  * Available since API level 33.
	  *
	  * @return manager instance on success, nullptr on failure.
	  */
	APerformanceHint_getManager :: proc() -> ^APerformanceHintManager ---

	/**
	* Creates a session for the given set of threads and sets their initial target work
	* duration.
	*
	* Available since API level 33.
	*
	* @param manager The performance hint manager instance.
	* @param threadIds The list of threads to be associated with this session. They must be part of
	*     this app's thread group.
	* @param size the size of threadIds.
	* @param initialTargetWorkDurationNanos The desired duration in nanoseconds for the new session.
	*     This must be positive.
	* @return manager instance on success, nullptr on failure.
	*/
	APerformanceHint_createSession :: proc(manager: ^APerformanceHintManager, threadIds: [^]i32, size: uint, initialTargetWorkDurationNanos: i64) -> ^APerformanceHintSession ---

	/**
	* Get preferred update rate information for this device.
	*
	* Available since API level 33.
	*
	* @param manager The performance hint manager instance.
	* @return the preferred update rate supported by device software.
	*/
	APerformanceHint_getPreferredUpdateRateNanos :: proc(manager: ^APerformanceHintManager) -> i64 ---

	/**
	* Updates this session's target duration for each cycle of work.
	*
	* Available since API level 33.
	*
	* @param session The performance hint session instance to update.
	* @param targetDurationNanos the new desired duration in nanoseconds. This must be positive.
	* @return 0 on success
	*         EINVAL if targetDurationNanos is not positive.
	*         EPIPE if communication with the system service has failed.
	*/
	APerformanceHint_updateTargetWorkDuration :: proc(session: ^APerformanceHintSession, targetDurationNanos: i64) -> i32 ---

	/**
	* Reports the actual duration for the last cycle of work.
	*
	* <p>The system will attempt to adjust the core placement of the threads within the thread
	* group and/or the frequency of the core on which they are run to bring the actual duration
	* close to the target duration.</p>
	*
	* Available since API level 33.
	*
	* @param session The performance hint session instance to update.
	* @param actualDurationNanos how long the thread group took to complete its last task in
	*     nanoseconds. This must be positive.
	* @return 0 on success
	*         EINVAL if actualDurationNanos is not positive.
	*         EPIPE if communication with the system service has failed.
	*/
	APerformanceHint_reportActualWorkDuration :: proc(session: ^APerformanceHintSession, actualDurationNanos: i64) -> i32 ---

	/**
	* Release the performance hint manager pointer acquired via
	* {@link APerformanceHint_createSession}.
	*
	* Available since API level 33.
	*
	* @param session The performance hint session instance to release.
	*/
	APerformanceHint_closeSession :: proc(session: ^APerformanceHintSession) ---

	/**
	 * Set a list of threads to the performance hint session. This operation will replace
	 * the current list of threads with the given list of threads.
	 *
	 * Available since API level 34.
	 *
	 * @param session The performance hint session instance to update.
	 * @param threadIds The list of threads to be associated with this session. They must be part of
	 *     this app's thread group.
	 * @param size The size of the list of threadIds.
	 * @return 0 on success.
	 *         EINVAL if the list of thread ids is empty or if any of the thread ids are not part of
	 *               the thread group.
	 *         EPIPE if communication with the system service has failed.
	 *         EPERM if any thread id doesn't belong to the application.
	 */
	APerformanceHint_setThreads :: proc(session: ^APerformanceHintSession, threadIds: [^]i32, size: uint) -> i32 ---

	/**
	 * This tells the session that these threads can be
	 * safely scheduled to prefer power efficiency over performance.
	 *
	 * Available since API level 35.
	 *
	 * @param session The performance hint session instance to update.
	 * @param enabled The flag which sets whether this session will use power-efficient scheduling.
	 * @return 0 on success.
	 *         EPIPE if communication with the system service has failed.
	 */
	APerformanceHint_setPreferPowerEfficiency :: proc(session: ^APerformanceHintSession, enabled: bool) -> i32 ---

	/**
	 * Reports the durations for the last cycle of work.
	 *
	 * The system will attempt to adjust the scheduling and performance of the
	 * threads within the thread group to bring the actual duration close to the target duration.
	 *
	 * Available since API level 35.
	 *
	 * @param session The {@link APerformanceHintSession} instance to update.
	 * @param workDuration The {@link AWorkDuration} structure of times the thread group took to
	 *     complete its last task in nanoseconds breaking down into different components.
	 *
	 *     The work period start timestamp and actual total duration must be greater than zero.
	 *
	 *     The actual CPU and GPU durations must be greater than or equal to zero, and at least one
	 *     of them must be greater than zero. When one of them is equal to zero, it means that type
	 *     of work was not measured for this workload.
	 *
	 * @return 0 on success.
	 *         EINVAL if any duration is an invalid number.
	 *         EPIPE if communication with the system service has failed.
	 */
	APerformanceHint_reportActualWorkDuration2 :: proc(session: ^APerformanceHintSession, workDuration: ^AWorkDuration) -> i32 ---

	/**
	 * Creates a new AWorkDuration. When the client finishes using {@link AWorkDuration}, it should
	 * call {@link AWorkDuration_release()} to destroy {@link AWorkDuration} and release all resources
	 * associated with it.
	 *
	 * Available since API level 35.
	 *
	 * @return AWorkDuration on success and nullptr otherwise.
	 */
	AWorkDuration_create :: proc() -> ^AWorkDuration ---

	/**
	 * Destroys {@link AWorkDuration} and free all resources associated to it.
	 *
	 * Available since API level 35.
	 *
	 * @param aWorkDuration The {@link AWorkDuration} created by calling {@link AWorkDuration_create()}
	 */
	AWorkDuration_release :: proc(aWorkDuration: ^AWorkDuration) ---

	/**
	 * Sets the work period start timestamp in nanoseconds.
	 *
	 * Available since API level 35.
	 *
	 * @param aWorkDuration The {@link AWorkDuration} created by calling {@link AWorkDuration_create()}
	 * @param workPeriodStartTimestampNanos The work period start timestamp in nanoseconds based on
	 *        CLOCK_MONOTONIC about when the work starts. This timestamp must be greater than zero.
	 */
	AWorkDuration_setWorkPeriodStartTimestampNanos :: proc(aWorkDuration: ^AWorkDuration, workPeriodStartTimestampNanos: i64) ---

	/**
	 * Sets the actual total work duration in nanoseconds.
	 *
	 * Available since API level 35.
	 *
	 * @param aWorkDuration The {@link AWorkDuration} created by calling {@link AWorkDuration_create()}
	 * @param actualTotalDurationNanos The actual total work duration in nanoseconds. This number must
	 *        be greater than zero.
	 */
	AWorkDuration_setActualTotalDurationNanos :: proc(aWorkDuration: ^AWorkDuration, actualTotalDurationNanos: i64) ---

	/**
	 * Sets the actual CPU work duration in nanoseconds.
	 *
	 * Available since API level 35.
	 *
	 * @param aWorkDuration The {@link AWorkDuration} created by calling {@link AWorkDuration_create()}
	 * @param actualCpuDurationNanos The actual CPU work duration in nanoseconds. This number must be
	 *        greater than or equal to zero. If it is equal to zero, that means the CPU was not
	 *        measured.
	 */
	AWorkDuration_setActualCpuDurationNanos :: proc(aWorkDuration: ^AWorkDuration, actualCpuDurationNanos: i64) ---

	/**
	 * Sets the actual GPU work duration in nanoseconds.
	 *
	 * Available since API level 35.
	 *
	 * @param aWorkDuration The {@link AWorkDuration} created by calling {@link AWorkDuration_create()}.
	 * @param actualGpuDurationNanos The actual GPU work duration in nanoseconds, the number must be
	 *        greater than or equal to zero. If it is equal to zero, that means the GPU was not
	 *        measured.
	 */
	AWorkDuration_setActualGpuDurationNanos :: proc(aWorkDuration: ^AWorkDuration, actualGpuDurationNanos: i64) ---
}

