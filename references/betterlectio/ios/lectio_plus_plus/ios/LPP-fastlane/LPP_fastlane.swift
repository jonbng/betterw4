//
//  LPP_fastlane.swift
//  LPP-fastlane
//
//  Created by Oscar Spalk on 05/08/2024.
//

import XCTest

final class LPP_fastlane: XCTestCase {
    
    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
        
        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false
        
        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }
    
    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }
    
    func loginToApp(app : XCUIApplication) {
        let startButton = app.buttons["Gå i gang"]
        startButton.waitForExistence(timeout: 30)
        startButton.tap()
        let nextButton = app.buttons["Videre"]
        nextButton.waitForExistence(timeout: 1)
        nextButton.tap()
        
        let choseButton = app.buttons["Vælg"]
        choseButton.waitForExistence(timeout: 1)
        choseButton.tap()
        
        app.typeText("egaa")
        let egaaField = app.staticTexts["Egaa Gymnasium"]
        egaaField.waitForExistence(timeout: 1)
        
        egaaField.tap()
        let usernameField = app.textFields["Brugernavn"]
        let passwordField = app.textFields["Kodeord"]
        
        usernameField.waitForExistence(timeout: 1)
        passwordField.waitForExistence(timeout: 1)
        usernameField.tap()
        app.typeText("olle")
        passwordField.tap()
        app.typeText("Zealot2022")
        
        app.buttons["Log ind"].tap()
        
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        
        
        let alert1 = springboard.alerts.buttons["Cancel"]
        let foundAlert1 = alert1.waitForExistence(timeout: 120)
        if(foundAlert1){
            alert1.tap()
        }
        
        
        
        let alert2 = springboard.alerts.buttons["Allow"]
        let foundAlert2 = alert2.waitForExistence(timeout: 10)
        if(foundAlert2){
            alert2.tap()
            
        }
        
        
        
        let alert3 = springboard.alerts.buttons["Allow"]
        
        let foundAlert3 = alert3.waitForExistence(timeout: 10)
        if(foundAlert3){
            alert3.tap()
        }
        
        let alert4 = findElement(app: app.buttons, search: "Giv samtykke")
        let foundAlert4 = alert4.waitForExistence(timeout: 10)
        if(foundAlert4){
            alert4.tap()
        }
    }
    
    
    
    
    
    func navigateToFravær(app: XCUIApplication) {
        let fraværButton = app.staticTexts["Fravær\nTab 3 of 5"]
        fraværButton.waitForExistence(timeout: 1)
        fraværButton.tap()
        app.staticTexts["%"].waitForExistence(timeout: 15)
    }
    
    func findElement(app: XCUIElementQuery, search : String) -> XCUIElement {
        let predicate = NSPredicate(format: "label CONTAINS[c] %@", search)
        let element = app.containing(predicate).element(boundBy: 0)
        return element
    }
    
    func switchYear(app: XCUIApplication) {
        let menuButton = app.staticTexts["Mere\nTab 5 of 5"]
        menuButton.waitForExistence(timeout: 1)
        menuButton.tap()
        
        app.swipeUp()
        
        let switchYearButton = findElement(app: app.staticTexts, search: "årgang")
        switchYearButton.waitForExistence(timeout: 1)
        switchYearButton.tap()
        
        let correctYearButton = findElement(app: app.buttons, search: "2023")
        correctYearButton.waitForExistence(timeout: 30)
        correctYearButton.tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert1 = springboard.alerts.buttons["Cancel"]
        let foundAlert1 = alert1.waitForExistence(timeout: 120)
        if(foundAlert1){
            alert1.tap()
        }
        
        findElement(app: app.staticTexts, search: "Uge").waitForExistence(timeout: 5)
    }
    
    func setupCalendar(app: XCUIApplication){
        let optionDial = app.buttons["option-dial"]
        optionDial.waitForExistence(timeout: 2)
        optionDial.tap()
        
        let choseDateButton = app.buttons["date-picker"]
        choseDateButton.waitForExistence(timeout: 2)
        choseDateButton.tap()
        
        let editButton = app.buttons["Switch to input"]
        editButton.waitForExistence(timeout: 2)
        editButton.tap()
        
        let dateField = app.textFields["Enter Date"]
        dateField.waitForExistence(timeout: 2)
        dateField.tap()
        let dateString = "4/25/2024"
        
        dateField.clearText()
        app.typeText(dateString)
        
        let okButton = findElement(app: app.buttons, search: "OK")
        okButton.waitForExistence(timeout: 2)
        okButton.tap()
        // required for testing with xcode
        if(okButton.exists){
            okButton.tap()
        }
        
        let adamElementCheck = findElement(app: app.staticTexts, search: "Varmelærens")
        adamElementCheck.waitForExistence(timeout: 30)
    }
    
    func navigateToOpgaver(app: XCUIApplication){
        let opgaverButton = app.staticTexts["Opgaver\nTab 4 of 5"]
        opgaverButton.waitForExistence(timeout: 2)
        opgaverButton.tap()
        
        let fab = app.buttons["assignment-filter"]
        fab.waitForExistence(timeout: 15)
        fab.tap()
        
        let correctFilter = findElement(app: app.buttons, search: "Afleveret")
        correctFilter.waitForExistence(timeout: 15)
        correctFilter.tap()
        
        app.tap()
        
        let elementCheck = findElement(app: app.staticTexts, search: "Uge")
        elementCheck.waitForExistence(timeout: 30)
    }
    
    @MainActor func testScreenshots() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()
        
        setupSnapshot(app)
        
        loginToApp(app: app)
        
        switchYear(app: app)
        
        // lets get to this date
        setupCalendar(app: app)
        
        snapshot("01Calendar")
        
        navigateToFravær(app: app)
        snapshot("02Absence")
        
        navigateToOpgaver(app: app)
        snapshot("03Opgaver")
        
        // Use XCTAssert and related functions to verify your tests produce the correct results.
        
        XCTAssert(true)
    }
    
    
    
    
}
