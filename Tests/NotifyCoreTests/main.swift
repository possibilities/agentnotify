import Foundation

class CheckCase {
    func setUpWithError() throws {}
    func tearDownWithError() throws {}
}
func expectEqual<T: Equatable>(_ lhs: @autoclosure () throws -> T, _ rhs: @autoclosure () throws -> T, file: StaticString = #file, line: UInt = #line) {
    do { let a = try lhs(), b = try rhs(); precondition(a == b, "Expected \(a) == \(b)", file: file, line: line) }
    catch { fatalError("Unexpected error: \(error)", file: file, line: line) }
}
func expectTrue(_ value: @autoclosure () throws -> Bool, file: StaticString = #file, line: UInt = #line) { expectEqual(try value(), true, file: file, line: line) }
func expectFalse(_ value: @autoclosure () throws -> Bool, file: StaticString = #file, line: UInt = #line) { expectEqual(try value(), false, file: file, line: line) }
func expectNil<T>(_ value: @autoclosure () throws -> T?, file: StaticString = #file, line: UInt = #line) { do { let result = try value(); precondition(result == nil, "Expected nil", file: file, line: line) } catch { fatalError("\(error)", file: file, line: line) } }
func expectThrows(_ value: @autoclosure () throws -> Any, file: StaticString = #file, line: UInt = #line) { do { _ = try value(); fatalError("Expected an error", file: file, line: line) } catch {} }
var checks = 0
func run(_ name: String, _ check: () throws -> Void) {
    do { try check(); checks += 1; print("PASS \(name)") }
    catch { fatalError("FAIL \(name): \(error)") }
}
run("ArgumentsTests.testLegacyActionsAndEscaping") { let suite = ArgumentsTests(); try suite.setUpWithError(); defer { try? suite.tearDownWithError() }; try suite.testLegacyActionsAndEscaping() }
run("ArgumentsTests.testPipedMessageAndListGrammar") { let suite = ArgumentsTests(); try suite.setUpWithError(); defer { try? suite.tearDownWithError() }; try suite.testPipedMessageAndListGrammar() }
run("ArgumentsTests.testModernTypedArguments") { let suite = ArgumentsTests(); try suite.setUpWithError(); defer { try? suite.tearDownWithError() }; try suite.testModernTypedArguments() }
run("ArgumentsTests.testShortcutJSONArguments") { let suite = ArgumentsTests(); try suite.setUpWithError(); defer { try? suite.tearDownWithError() }; try suite.testShortcutJSONArguments() }
run("ArgumentsTests.testScheduleValidation") { let suite = ArgumentsTests(); try suite.setUpWithError(); defer { try? suite.tearDownWithError() }; try suite.testScheduleValidation() }
run("ArgumentsTests.testCatalogHasMatchingToolSchemas") { let suite = ArgumentsTests(); try suite.setUpWithError(); defer { try? suite.tearDownWithError() }; suite.testCatalogHasMatchingToolSchemas() }
run("StoreTests.testReadAndCompletionSurviveReopen") { let suite = StoreTests(); try suite.setUpWithError(); defer { try? suite.tearDownWithError() }; try suite.testReadAndCompletionSurviveReopen() }
run("StoreTests.testCompleteAllAtomicallyFinishesOnlyTheInbox") { let suite = StoreTests(); try suite.setUpWithError(); defer { try? suite.tearDownWithError() }; try suite.testCompleteAllAtomicallyFinishesOnlyTheInbox() }
run("StoreTests.testGroupReplacementRetainsAndResolvesEarlierPrompt") { let suite = StoreTests(); try suite.setUpWithError(); defer { try? suite.tearDownWithError() }; try suite.testGroupReplacementRetainsAndResolvesEarlierPrompt() }
run("StoreTests.testIdempotencyConflictAndNoDuplicateEffects") { let suite = StoreTests(); try suite.setUpWithError(); defer { try? suite.tearDownWithError() }; try suite.testIdempotencyConflictAndNoDuplicateEffects() }
run("StoreTests.testConcurrentResponsesHaveOneWinner") { let suite = StoreTests(); try suite.setUpWithError(); defer { try? suite.tearDownWithError() }; try suite.testConcurrentResponsesHaveOneWinner() }
run("StoreTests.testOptimisticConcurrencyAndTransactionalFailure") { let suite = StoreTests(); try suite.setUpWithError(); defer { try? suite.tearDownWithError() }; try suite.testOptimisticConcurrencyAndTransactionalFailure() }
run("StoreTests.testBatchStatusIsAtomicAndSupportsFriendlySnooze") { let suite = StoreTests(); try suite.setUpWithError(); defer { try? suite.tearDownWithError() }; try suite.testBatchStatusIsAtomicAndSupportsFriendlySnooze() }
run("StoreTests.testDeadlineAndSnoozeRemainDurableTasks") { let suite = StoreTests(); try suite.setUpWithError(); defer { try? suite.tearDownWithError() }; try suite.testDeadlineAndSnoozeRemainDurableTasks() }
run("StoreTests.testChangePaginationAndResume") { let suite = StoreTests(); try suite.setUpWithError(); defer { try? suite.tearDownWithError() }; try suite.testChangePaginationAndResume() }
run("StoreTests.testRemoveDoesNotDeleteHistory") { let suite = StoreTests(); try suite.setUpWithError(); defer { try? suite.tearDownWithError() }; try suite.testRemoveDoesNotDeleteHistory() }
run("StoreTests.testRepliesAreLiteralAndActionIndexPreservesDuplicateLabels") { let suite = StoreTests(); try suite.setUpWithError(); defer { try? suite.tearDownWithError() }; try suite.testRepliesAreLiteralAndActionIndexPreservesDuplicateLabels() }
run("StoreTests.testBadTypesAndUnknownArgumentsAreRejected") { let suite = StoreTests(); try suite.setUpWithError(); defer { try? suite.tearDownWithError() }; try suite.testBadTypesAndUnknownArgumentsAreRejected() }
run("StoreTests.testAttachmentsPersistWithoutNativePermission") { let suite = StoreTests(); try suite.setUpWithError(); defer { try? suite.tearDownWithError() }; try suite.testAttachmentsPersistWithoutNativePermission() }
run("StoreTests.testLegacySystemDeliveryIsNormalizedWithoutHidingContentWarnings") { let suite = StoreTests(); try suite.setUpWithError(); defer { try? suite.tearDownWithError() }; try suite.testLegacySystemDeliveryIsNormalizedWithoutHidingContentWarnings() }
run("StoreTests.testLargePagesRemainWithinTransportLimit") { let suite = StoreTests(); try suite.setUpWithError(); defer { try? suite.tearDownWithError() }; try suite.testLargePagesRemainWithinTransportLimit() }
run("ArrivalChecks.testStartupCursorDoesNotReplayBacklog") { try ArrivalChecks().testStartupCursorDoesNotReplayBacklog() }
run("ArrivalChecks.testFreshArrivalsCoalesceInEventOrderAndReplaySafely") { try ArrivalChecks().testFreshArrivalsCoalesceInEventOrderAndReplaySafely() }
run("ArrivalChecks.testReadAndDeliveryChangesStaySilent") { try ArrivalChecks().testReadAndDeliveryChangesStaySilent() }
run("ArrivalChecks.testGroupReplacementEmitsOnlyCreatedReplacement") { try ArrivalChecks().testGroupReplacementEmitsOnlyCreatedReplacement() }
run("ArrivalChecks.testFutureScheduleStaysSilentUntilDurableDueChange") { try ArrivalChecks().testFutureScheduleStaysSilentUntilDurableDueChange() }
run("ArrivalChecks.testDueSnoozedTaskCanArriveWithExistingResponse") { try ArrivalChecks().testDueSnoozedTaskCanArriveWithExistingResponse() }
run("ArrivalChecks.testReopenAndResolvedOrHiddenChangesStaySilent") { try ArrivalChecks().testReopenAndResolvedOrHiddenChangesStaySilent() }
run("ArrivalChecks.testCursorGapFailsWithoutAdvancing") { try ArrivalChecks().testCursorGapFailsWithoutAdvancing() }
run("preferences.persistence_and_isolation") { let suite = PreferencesChecks(); try suite.setUpWithError(); defer { try? suite.tearDownWithError() }; try suite.persistenceAndIsolation() }
run("preferences.shortcut_migration_persistence_clearing_and_validation") { let suite = PreferencesChecks(); try suite.setUpWithError(); defer { try? suite.tearDownWithError() }; try suite.shortcutMigrationPersistenceClearingAndValidation() }
run("preferences.retired_banner_field_compatibility") { let suite = PreferencesChecks(); try suite.setUpWithError(); defer { try? suite.tearDownWithError() }; try suite.bannerReminderMigrationAndIndependentUpdates() }
run("preferences.conflicts_and_replay") { let suite = PreferencesChecks(); try suite.setUpWithError(); defer { try? suite.tearDownWithError() }; try suite.conflictsAndReplay() }
run("preferences.concurrent_clients_and_service_routing") { let suite = PreferencesChecks(); try suite.setUpWithError(); defer { try? suite.tearDownWithError() }; try suite.concurrentClientsAndServiceRouting() }
run("interface.routing_and_headless_failure") { let suite = InterfaceChecks(); try suite.setUpWithError(); defer { try? suite.tearDownWithError() }; try suite.routingAndHeadlessFailure() }
run("shim.offer_durability_and_missing_installer") { let suite = ShimChecks(); try suite.setUpWithError(); defer { try? suite.tearDownWithError() }; try suite.offerDurabilityAndUnavailableInstaller() }
run("shim.owner_delegation_and_detection") { let suite = ShimChecks(); try suite.setUpWithError(); defer { try? suite.tearDownWithError() }; try suite.installerDelegationAndDetection() }
run("shim.original_notifier_blocks_install") { let suite = ShimChecks(); try suite.setUpWithError(); defer { try? suite.tearDownWithError() }; try suite.originalNotifierBlocksInstallAndIsIgnoredWhenItIsTheManagedRouter() }
print("\(checks) core checks passed.")
