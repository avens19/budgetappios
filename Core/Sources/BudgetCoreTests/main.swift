import Foundation

// Swift has no way to discover test functions by reflection, so they are listed.
// A test that is written but not listed here does not run, which is the one
// failure mode of this arrangement worth being careful about.

print("BudgetCore")

print("\n  budget weeks")
test("weekStartRespectsStartDay", BudgetCalendarTests.test_weekStartRespectsStartDay)
test("startDayIsItsOwnWeekStart", BudgetCalendarTests.test_startDayIsItsOwnWeekStart)
test("weekEndIsExclusive", BudgetCalendarTests.test_weekEndIsExclusive)
test("monthWeeks", BudgetCalendarTests.test_monthWeeks)
test("monthStepping", BudgetCalendarTests.test_monthStepping)
test("daysLeft", BudgetCalendarTests.test_daysLeft)
test("todayUsesLocalDay", BudgetCalendarTests.test_todayUsesLocalDay)

print("  wire dates")
test("roundTrip", WireDateTests.test_roundTrip)
test("lenientParsing", WireDateTests.test_lenientParsing)
test("rejectsGarbage", WireDateTests.test_rejectsGarbage)
test("decodesServerPayload", WireDateTests.test_decodesServerPayload)
test("nullFlagsDefaultToFalse", WireDateTests.test_nullFlagsDefaultToFalse)
test("encodesBareDay", WireDateTests.test_encodesBareDay)

print("  watermarks")
test("takesEarlier", WatermarkTests.test_takesEarlier)
test("missingHeaderMeansNil", WatermarkTests.test_missingHeaderMeansNil)
test("equalIsFine", WatermarkTests.test_equalIsFine)
test("lexicographicOrderingHolds", WatermarkTests.test_lexicographicOrderingHolds)

print("  sync engine")
await test("pullsFromTheStoredWatermark", SyncEngineTests.test_pullsFromTheStoredWatermark)
await test("createdRowsAreReplaced", SyncEngineTests.test_createdRowsAreReplaced)
await test("localOnlyDeleteSkipsTheServer", SyncEngineTests.test_localOnlyDeleteSkipsTheServer)
await test("syncedDeleteHitsTheServer", SyncEngineTests.test_syncedDeleteHitsTheServer)
await test("categoriesGoFirst", SyncEngineTests.test_categoriesGoFirst)
await test("appliesBeforeAdvancing", SyncEngineTests.test_appliesBeforeAdvancing)
await test("doesNotAdvanceWithoutAHeader", SyncEngineTests.test_doesNotAdvanceWithoutAHeader)
await test("storesTheEarlierWatermark", SyncEngineTests.test_storesTheEarlierWatermark)

print("  category palette")
test("slotsByIdRank", CategoryPaletteTests.test_slotsByIdRank)
test("noSlotForUnknown", CategoryPaletteTests.test_noSlotForUnknown)
test("wrapsAtTen", CategoryPaletteTests.test_wrapsAtTen)
test("deletedAreExcluded", CategoryPaletteTests.test_deletedAreExcluded)
test("breakdownExcludesSystemRows", CategoryPaletteTests.test_breakdownExcludesSystemRows)
test("breakdownDropsNegativeBuckets", CategoryPaletteTests.test_breakdownDropsNegativeBuckets)
test("orphansJoinUncategorized", CategoryPaletteTests.test_orphansJoinUncategorized)
test("breakdownIsSortedDescending", CategoryPaletteTests.test_breakdownIsSortedDescending)

print("  weekly number")
test("annualisesEachPeriod", WeeklyNumberTests.test_annualisesEachPeriod)
test("treatsUnusableAmountsAsNothing", WeeklyNumberTests.test_treatsUnusableAmountsAsNothing)
test("readsACommaDecimalSeparator", WeeklyNumberTests.test_readsACommaDecimalSeparator)
test("dividesWhatIsLeftAcrossFiftyTwoWeeks", WeeklyNumberTests.test_dividesWhatIsLeftAcrossFiftyTwoWeeks)
test("reportsAShortfallAsNegative", WeeklyNumberTests.test_reportsAShortfallAsNegative)
test("totalsSplitIncomeFromOutgoing", WeeklyNumberTests.test_totalsSplitIncomeFromOutgoing)
test("totalsHonourAChangedPeriod", WeeklyNumberTests.test_totalsHonourAChangedPeriod)
test("asksSeventeenPromptsInThreeGroups", WeeklyNumberTests.test_asksSeventeenPromptsInThreeGroups)

print("  invite links")
test("readsTheToken", InviteLinkTests.test_readsTheToken)
test("acceptsBase64urlAlphabet", InviteLinkTests.test_acceptsBase64urlAlphabet)
test("rejectsEverythingElse", InviteLinkTests.test_rejectsEverythingElse)
test("rejectsPathTricks", InviteLinkTests.test_rejectsPathTricks)
test("ignoresQueryAndFragment", InviteLinkTests.test_ignoresQueryAndFragment)

print()
exit(report())
