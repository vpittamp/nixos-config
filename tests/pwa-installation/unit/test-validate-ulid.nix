# Unit Tests for validateULID Function (TR-001, TR-004, TR-005)
# These tests must FAIL initially until validateULID is implemented
{ pkgs ? import <nixpkgs> {} }:

let
  # Import test fixtures
  testPWAs = import /etc/nixos/tests/pwa-installation/fixtures/test-pwas.nix { lib = pkgs.lib; };

  # Import the actual validateULID function from pwa-sites.nix
  # Note: We're testing the implementation in pwa-sites.nix which is reused in firefox-pwas-declarative.nix
  pwaSitesConfig = import /etc/nixos/shared/pwa-sites.nix { lib = pkgs.lib; };
  validateULID = pwaSitesConfig.validateULID;

  # Test helper
  runTest = name: assertion: expectedResult:
    if assertion == expectedResult
    then { inherit name; result = "PASS"; }
    else { inherit name; result = "FAIL"; expected = expectedResult; actual = assertion; };

in
pkgs.runCommand "test-validate-ulid" {} ''
  mkdir -p $out

  echo "Running validateULID unit tests..." > $out/results.txt
  echo "===================================" >> $out/results.txt
  echo "" >> $out/results.txt

  # T007: Test valid ULID
  ${pkgs.lib.concatMapStrings (testCase: ''
    echo "Test: ${testCase.name}" >> $out/results.txt
    result="${if testCase.result == "PASS" then "✓" else "✗"}"
    echo "$result ${testCase.result}" >> $out/results.txt
    ${if testCase.result == "FAIL" then ''
      echo "  Expected: ${toString testCase.expected}" >> $out/results.txt
      echo "  Actual: ${toString testCase.actual}" >> $out/results.txt
    '' else ""}
    echo "" >> $out/results.txt
  '') [
    # T007: Valid ULID should return true
    (runTest "Valid ULID - minimal PWA" (validateULID testPWAs.minimal.ulid) true)
    (runTest "Valid ULID - complete PWA" (validateULID testPWAs.complete.ulid) true)
    (runTest "Valid ULID - YouTube example" (validateULID testPWAs.youtubeExample.ulid) true)

    # T008: Invalid ULID with forbidden characters (I, L, O, U)
    (runTest "Invalid ULID - contains forbidden chars" (validateULID testPWAs.invalidUlidChars.ulid) false)
    (runTest "Invalid ULID - contains 'I'" (validateULID "01HQTEST000000000INVALID0") false)
    (runTest "Invalid ULID - contains 'O'" (validateULID "01HQTEST00000000000000O0") false)
    (runTest "Invalid ULID - contains 'L'" (validateULID "01HQTEST00000000000000L0") false)
    (runTest "Invalid ULID - contains 'U'" (validateULID "01HQTEST00000000000000U0") false)

    # T009: Invalid ULID length
    (runTest "Invalid ULID - too short (25 chars)" (validateULID "01HQTEST0000000000000000") false)
    (runTest "Invalid ULID - too long (27 chars)" (validateULID "01HQTEST0000000000000000001") false)
    (runTest "Invalid ULID - way too long" (validateULID testPWAs.invalidUlidLength.ulid) false)
    (runTest "Invalid ULID - empty string" (validateULID "") false)

    # Additional edge cases
    (runTest "Invalid ULID - lowercase (ULIDs are uppercase)" (validateULID "01hqtest000000000000000001") false)
    (runTest "Invalid ULID - contains special chars" (validateULID "01HQTEST00000000000000-01") false)
    (runTest "Invalid ULID - contains spaces" (validateULID "01HQTEST 00000000000000001") false)
  ]}

  # Count results
  TOTAL=$(grep -c "^Test:" $out/results.txt || echo 0)
  PASSED=$(grep -c "✓ PASS" $out/results.txt || echo 0)
  FAILED=$(grep -c "✗ FAIL" $out/results.txt || echo 0)

  echo "===================================" >> $out/results.txt
  echo "Summary: $PASSED passed, $FAILED failed out of $TOTAL tests" >> $out/results.txt

  # Show results
  cat $out/results.txt

  # Fail the test if any tests failed (TDD RED phase expected)
  if [ $FAILED -gt 0 ]; then
    echo "" >> $out/results.txt
    echo "❌ EXPECTED FAILURE (TDD RED phase)" >> $out/results.txt
    echo "Implement validateULID in firefox-pwas-declarative.nix to make these tests pass" >> $out/results.txt
    exit 1
  fi
''
