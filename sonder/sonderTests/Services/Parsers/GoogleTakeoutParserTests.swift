//
//  GoogleTakeoutParserTests.swift
//  sonderTests
//
//  Created by Michael Song on 2/25/26.
//

import Testing
import Foundation
import CoreLocation
@testable import sonder

@Suite(.serialized)
struct GoogleTakeoutParserTests {

    // MARK: - GeoJSON Parsing

    @Test func parseGeoJSON_validFile_returnsEntries() throws {
        let data = Self.sampleGeoJSON.data(using: .utf8)!
        let entries = try GoogleTakeoutParser.parseGeoJSON(data: data)

        #expect(entries.count == 3)

        #expect(entries[0].name == "Joe's Pizza")
        #expect(entries[0].address == "7 Carmine St, New York, NY 10014")
        #expect(entries[0].coordinate != nil)
        #expect(entries[0].coordinate!.latitude == 40.7128)
        #expect(entries[0].coordinate!.longitude == -74.006)
        #expect(entries[0].sourceURL == "http://maps.google.com/?cid=12345678901234567")

        #expect(entries[1].name == "Tartine Bakery")
        #expect(entries[1].coordinate!.latitude == 37.7749)

        #expect(entries[2].name == "Ramen Nagi")
        #expect(entries[2].coordinate!.latitude == 35.6895)
    }

    @Test func parseGeoJSON_dateExtraction() throws {
        let data = Self.sampleGeoJSON.data(using: .utf8)!
        let entries = try GoogleTakeoutParser.parseGeoJSON(data: data)

        // First entry has a Published date
        #expect(entries[0].dateAdded != nil)
        // Other entries don't
        #expect(entries[1].dateAdded == nil)
    }

    @Test func parseGeoJSON_emptyFeatures_returnsEmpty() throws {
        let json = """
        {"type": "FeatureCollection", "features": []}
        """
        let entries = try GoogleTakeoutParser.parseGeoJSON(data: json.data(using: .utf8)!)
        #expect(entries.isEmpty)
    }

    @Test func parseGeoJSON_missingFeaturesKey_throwsError() {
        let json = """
        {"type": "FeatureCollection", "items": []}
        """
        #expect(throws: ImportParseError.self) {
            try GoogleTakeoutParser.parseGeoJSON(data: json.data(using: .utf8)!)
        }
    }

    @Test func parseGeoJSON_invalidJSON_throwsError() {
        let data = "not json at all".data(using: .utf8)!
        #expect(throws: (any Error).self) {
            try GoogleTakeoutParser.parseGeoJSON(data: data)
        }
    }

    @Test func parseGeoJSON_featureWithoutTitle_skipped() throws {
        let json = """
        {"type": "FeatureCollection", "features": [
            {"geometry": {"coordinates": [-74, 40], "type": "Point"},
             "properties": {"Google Maps URL": "http://maps.google.com/?cid=123"},
             "type": "Feature"}
        ]}
        """
        let entries = try GoogleTakeoutParser.parseGeoJSON(data: json.data(using: .utf8)!)
        #expect(entries.isEmpty)
    }

    @Test func parseGeoJSON_fallbackToLocationProperties() throws {
        let json = """
        {"type": "FeatureCollection", "features": [
            {"geometry": {"coordinates": [0, 0], "type": "Point"},
             "properties": {
                "Title": "Test Place",
                "Location": {"Latitude": "48.8566", "Longitude": "2.3522"}
             },
             "type": "Feature"}
        ]}
        """
        let entries = try GoogleTakeoutParser.parseGeoJSON(data: json.data(using: .utf8)!)
        #expect(entries.count == 1)
        #expect(entries[0].coordinate!.latitude == 48.8566)
        #expect(entries[0].coordinate!.longitude == 2.3522)
    }

    // MARK: - CSV Parsing

    @Test func parseCSV_validFile_returnsEntries() throws {
        let entries = try GoogleTakeoutParser.parseCSV(content: Self.sampleCSV, listName: "Want to Go")

        #expect(entries.count == 3)
        #expect(entries[0].name == "Blue Bottle Coffee")
        #expect(entries[0].sourceURL == "http://maps.google.com/?cid=22222222222222222")
        #expect(entries[1].name == "Cafe de Flore")
        #expect(entries[2].name == "Dishoom")
    }

    @Test func parseCSV_preservesListName() throws {
        let entries = try GoogleTakeoutParser.parseCSV(content: Self.sampleCSV, listName: "My Favorites")

        // CSV entries with empty Note get listName from parameter
        #expect(entries[0].sourceListName == "My Favorites")
    }

    @Test func parseCSV_emptyFile_throwsError() {
        #expect(throws: ImportParseError.self) {
            try GoogleTakeoutParser.parseCSV(content: "", listName: nil)
        }
    }

    @Test func parseCSV_missingTitleColumn_throwsError() {
        let csv = "Name,URL\n\"Place\",\"http://example.com\""
        #expect(throws: ImportParseError.self) {
            try GoogleTakeoutParser.parseCSV(content: csv, listName: nil)
        }
    }

    @Test func parseCSV_emptyTitle_skipped() throws {
        let csv = "Title,URL\n\"\",\"http://maps.google.com\"\n\"Real Place\",\"http://maps.google.com\""
        let entries = try GoogleTakeoutParser.parseCSV(content: csv, listName: nil)
        #expect(entries.count == 1)
        #expect(entries[0].name == "Real Place")
    }

    @Test func parseCSV_quotedFieldWithComma() throws {
        let csv = "Title,Note,URL,Comment\n\"Joe's Diner, LLC\",\"\",\"http://maps.google.com\",\"\""
        let entries = try GoogleTakeoutParser.parseCSV(content: csv, listName: nil)
        #expect(entries.count == 1)
        #expect(entries[0].name == "Joe's Diner, LLC")
    }

    @Test func parseCSV_headerOnly_returnsEmpty() throws {
        let csv = "Title,Note,URL,Comment\n"
        let entries = try GoogleTakeoutParser.parseCSV(content: csv, listName: nil)
        #expect(entries.isEmpty)
    }

    // MARK: - URL Place ID Extraction

    @Test func extractPlaceID_cidParameter() {
        let url = "http://maps.google.com/?cid=12345678901234567"
        let result = GoogleTakeoutParser.extractPlaceID(from: url)
        #expect(result == "cid:12345678901234567")
    }

    @Test func extractPlaceID_chijStyleID() {
        let url = "https://www.google.com/maps/place/Some+Place/data=!3m1!4b1!4m5!3m4!1sChIJN1t_tDeuEmsRUsoyG83frY4!8m2!3d-33.8!4d151.2"
        let result = GoogleTakeoutParser.extractPlaceID(from: url)
        #expect(result == "ChIJN1t_tDeuEmsRUsoyG83frY4")
    }

    @Test func extractPlaceID_noPlaceID_returnsNil() {
        let url = "https://www.google.com/maps/@37.7749,-122.4194,15z"
        let result = GoogleTakeoutParser.extractPlaceID(from: url)
        #expect(result == nil)
    }

    @Test func extractPlaceID_invalidURL_returnsNil() {
        let result = GoogleTakeoutParser.extractPlaceID(from: "not a url")
        #expect(result == nil)
    }

    // MARK: - File Type Detection

    @Test func parse_unsupportedExtension_throwsError() {
        let url = URL(fileURLWithPath: "/tmp/test.xml")
        #expect(throws: ImportParseError.self) {
            try GoogleTakeoutParser.parse(fileURL: url)
        }
    }

    // MARK: - Test Data

    private static let sampleGeoJSON = """
    {
      "type": "FeatureCollection",
      "features": [
        {
          "geometry": {"coordinates": [-74.006, 40.7128], "type": "Point"},
          "properties": {
            "Title": "Joe's Pizza",
            "Google Maps URL": "http://maps.google.com/?cid=12345678901234567",
            "Location": {"Latitude": "40.7128", "Longitude": "-74.006"},
            "Address": "7 Carmine St, New York, NY 10014",
            "Published": "2025-06-15T10:30:00Z"
          },
          "type": "Feature"
        },
        {
          "geometry": {"coordinates": [-122.4194, 37.7749], "type": "Point"},
          "properties": {
            "Title": "Tartine Bakery",
            "Google Maps URL": "http://maps.google.com/?cid=98765432109876543",
            "Location": {"Latitude": "37.7749", "Longitude": "-122.4194"}
          },
          "type": "Feature"
        },
        {
          "geometry": {"coordinates": [139.6917, 35.6895], "type": "Point"},
          "properties": {
            "Title": "Ramen Nagi",
            "Google Maps URL": "http://maps.google.com/?cid=11111111111111111"
          },
          "type": "Feature"
        }
      ]
    }
    """

    private static let sampleCSV = """
    Title,Note,URL,Comment
    "Blue Bottle Coffee","","http://maps.google.com/?cid=22222222222222222",""
    "Cafe de Flore","Best croissants","http://maps.google.com/?cid=33333333333333333",""
    "Dishoom","","http://maps.google.com/?cid=44444444444444444",""
    """
}
