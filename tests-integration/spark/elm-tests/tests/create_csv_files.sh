#!/bin/bash

#   Copyright 2022 Morgan Stanley
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.


#
# This script runs Elm tests with Antiques data in CSV format generated by GenerateAntiqueTestData.elm
#
# The output of the tests is written to CSV files which can be used as expected results in the
# corresponding Spark/Scala test for a particular rule in the Elm Antiques model.
#
set -ex

TEST_OUTPUT_DIR=$(mktemp -d -t elm-tests-XXXXXXXXXX)

SPARK_TEST_DATA_DIR=../../test/src/spark_test_data
mkdir -p "$SPARK_TEST_DATA_DIR"

for genFile in Generate*.elm
do
    fileName="$(grep "Debug.log" "$genFile" | sed 's:[^"]\+"\([^"]\+\)".*:\1:g')"
    testResultFile="$(mktemp --tmpdir="$TEST_OUTPUT_DIR")"
    elm-test "$genFile" > "$testResultFile"
    grep -m1 "$fileName" "$testResultFile" | sed -e 's?'"$fileName"': \["??' -e 's?",",?\n?g' -e 's?"]??' > "$SPARK_TEST_DATA_DIR/$fileName"

    echo -n '    """' | cat - "$SPARK_TEST_DATA_DIR/$fileName" > "$TEST_OUTPUT_DIR/$fileName.in"
    echo '"""' >> "$TEST_OUTPUT_DIR/$fileName.in"
    dataSourceName="$(echo "$genFile" | sed 's:Generate\(\w\+\).elm:\1Source.elm:')"
    tempOutput="$(mktemp --tmpdir="$TEST_OUTPUT_DIR")"
   
    cat "../src/$dataSourceName" \
        | sed -e '/^    """/,/^"""/d' \
        | sed -e "/^csvData =/ r $TEST_OUTPUT_DIR/$fileName.in" > "$tempOutput"
    cp "$tempOutput" "../src/$dataSourceName"

done


elmTestOutputToCsv () {

    elm-test "$1" > "$TEST_OUTPUT_DIR/$2.txt"
    grep -m1 "expected_results_$2.csv" "$TEST_OUTPUT_DIR/$2.txt" |sed -e "s?expected_results_$2.csv: Ok \"??" -e 's?"??g' -e 's?\\r\\n?\n?g' \
    > "$SPARK_TEST_DATA_DIR/expected_results_$2.csv"
}

skippedFiles="TestAntiqueSSFilter.elm  
TestAntiqueSSMapAndFilter.elm
TestAntiqueSSMapAndFilter2.elm 
TestAntiqueSSMapAndFilter3.elm"


for fileName in Test*.elm
do

    if grep -q "$fileName" <<< "$skippedFiles"
    then 
    continue
    fi
    testName="$(grep "executeTest" "$fileName" | grep -v '^import' | sed 's:[^"]\+"\([^"]\+\)".*:\1:g')"
    elmTestOutputToCsv $fileName $testName
    
done
