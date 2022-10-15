{--
   Copyright 2022 Morgan Stanley

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License. 
--}


module AntiqueProductDataSource exposing (antiqueProductDataSource)

import Csv.Decode as Decode exposing (..)
import CsvUtils exposing (..)
import SparkTests.Types exposing (..)


csvData : String
csvData =
    """product
Paintings
Knife
Plates
Furniture
HistoryWritings
"""


antiqueProductDataSource : Result Error (List ProductRecord)
antiqueProductDataSource =
    Decode.decodeCsv Decode.FieldNamesFromFirstRow antiqueProductDecoder csvData
