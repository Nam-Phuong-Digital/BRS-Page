//
//  InstallmentFee_VMTests.swift
//  PayooMerchantTests
//
//  Created by Dai Pham on 25/4/24.
//  Copyright © 2024 VietUnion. All rights reserved.
//

import XCTest
import RxSwift
import RxTest
import RxCocoa
import Domain
@testable import PayooMerchant

let resolution: TimeInterval = 0.2 // seconds

let MONEY_AMOUNT_9026:Double = 9_026_000
let MONEY_AMOUNT_3501:Double = Double(InstallmentFeeMoneyWithErrorMock.RequireInputMoreTheFirstNumberCard)
let MONEY_AMOUNT_3502:Double = Double(InstallmentFeeMoneyWithErrorMock.RequireChoseAConversationFee)
let MONEY_AMOUNT_3503:Double = Double(InstallmentFeeMoneyWithErrorMock.CardNotSupported)
let MONEY_AMOUNT_3504:Double = Double(InstallmentFeeMoneyWithErrorMock.BelowMin)
let MONEY_AMOUNT_3505:Double = Double(InstallmentFeeMoneyWithErrorMock.AboveMax)
let MONEY_AMOUNT_3506:Double = Double(InstallmentFeeMoneyWithErrorMock.CardNotBelongToBank)
let MONEY_AMOUNT_3507:Double = Double(InstallmentFeeMoneyWithErrorMock.SupportPeriodNotSupported)
let MONEY_AMOUNT_FOR_CARD_BELONG_TO_ANOTHER_BANK:Double = Double(InstallmentFeeMoneyWithErrorMock.CardBelongToAnotherBank)
let MONEY_AMOUNT_FOR_ERROR_1:Double = Double(InstallmentFeeMoneyWithErrorMock.DefaultError)

fileprivate enum InstallmentFeeMoneyWithErrorMock {
    static let RequireInputMoreTheFirstNumberCard = 3_501_000
    static let RequireChoseAConversationFee = 3_502_000
    static let CardNotSupported = 3_503_000
    static let BelowMin = 3_504_000
    static let AboveMax = 3_505_000
    static let CardNotBelongToBank = 3_506_000
    static let SupportPeriodNotSupported = 3_507_000
    
    static let DefaultError = 3_170_000 // purpose error -1
    static let CardBelongToAnotherBank = 3_180_000 // add to check card not belong to current bank
}

final class InstallmentFee_VMTests: XCTestCase {

    let userDefaultMock = UserDefaultsService_InstallmentFee_Mock()
    lazy var viewModel:InstallmentFeeViewModel = .init(
        bankUC: InstallmentBankUseCase(apiService: ApiServiceMock()),
        feeUC: InstallmentFeeChargeUseCase(apiService: ApiServiceMock()),
        shopUC: InstallmentShopUseCase(apiService: ApiServiceMock()),
        sessionUC: container.resolve(SessionUseCase.self)!,
        featureUC: FeaturesUseCase(userDefaultsService: userDefaultMock, profileUC: container.resolve(ProfileUseCase.self)!)
    )
    
    let events = ["x": ()] // simulate user press request button
    
    var disposeBag = DisposeBag()
    
    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
        userDefaultMock.permission = [.installmentFeeCheckOnline,.installmentFeeCheckInStore]
        viewModel.banks = [.stb,.vib]
        viewModel.shops = [.shop1,.shop2]
        viewModel.periods.accept([3]) // default 3
        viewModel.viewDidLoad()
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        viewModel.reset()
        disposeBag = DisposeBag()
    }
    
    func testInstallmentFee_MoneyAmount() {
        
        let scheduler = TestScheduler(initialClock: 0, resolution: 0, simulateProcessingDelay: true)
        
        // Set up all valid conditions to check the validation of a money amount.
        viewModel.currentSelectedBank.accept(.stb)
        viewModel.currentSelectedShop.accept(.shop1)
        viewModel.currentSelectedShopDomain.accept(Shop.shop1.shopDomains.first)
        
        let events:[String: Any?] = [
            // x represents the action when the request button is pressed.
            "x": (),
            // All keys with the prefix 't' represent the action when the user inputs the money amount.
            "t0": nil,
            "t": Double(500_000),
            "t1": Double(510_000),
            "t2": Double(5_000_000),
            "t4": Double(1_000_000),
            "t5": Double(1_100_000_000),
            // All keys with prefix 'c' represent the action when the user select installment type
            "c": InstallmentFeeCheckingType.counter,
            "c1": InstallmentFeeCheckingType.online,
            // All keys with the prefix 'b' represent the action when the user select a bank
            "b" : InstallmentBank.stb,
            "b1": InstallmentBank.vib
        ]
        
        let setupEvents: [String] = [
            // Case 1. Validate that the money amount has been inputted.
            "x-t-x-t1-x-t2-x-t0-x",
            // Case 2. Validate that the money amount inputed with installment fee type online
            "c1-t0-b-x-t-x-t2-x-b1-t4-x-t5-x"
        ]
        // Set up events and times.
        let scheduleEvents = scheduler.parseEventsAndTimes(
            timeline:  setupEvents.joined(separator: "-") + "--",
            values: events
        ).first!
        
        let expectedCase1: [InstallmentFeeChargeState] = [
            // Press the request button.
            .prepare,
            .error(BaseError()),
            // Press the request button with the money amount set to t.
            .prepare,
            .haveFee,
            // Press the request button with the money amount set to t1.
            .prepare,
            .haveFee,
            // Press the request button with the money amount set to t2.
            .prepare,
            .haveFee,
            // Press the request button with the money amount set to t0.
            .prepare,
            .error(BaseError())
        ]
        
        let expectedCase2: [InstallmentFeeChargeState] = [
            // change to installment type online
            .prepare,
            // input: type counter, money amount set to nil, select a bank then press the request button.
            .prepare,
            .error(BaseError()),
            // Input: money amount: t then press the request button.
            .prepare,
            .error(BaseError("money < min supported")),
            // Press the request button with the money amount set to t2.
            .prepare,
            .haveFee,
            // Select another bank and input money amount t4 then press the request button.
            .prepare,
            .error(BaseError("money < min supported")),
            // Select another bank and input money amount t5 then press the request button.
            .prepare,
            .error(BaseError("money > max supported"))
        ]
        
        let expected =
        expectedCase1 +
        expectedCase2
        
        // Observable events timeline.
        scheduler.createHotObservable(scheduleEvents)
            .debug("🔤")
            .subscribe(onNext: {[unowned self] input in
                if input is Void {
                    self.viewModel.getInstallmentFeeCharge()
                } else if let bank = input as? InstallmentBank {
                    self.viewModel.currentSelectedBank.accept(bank)
                } else if let shop = input as? Shop {
                    self.viewModel.currentSelectedShop.accept(shop)
                } else if let type = input as? InstallmentFeeCheckingType {
                    self.viewModel.installmentCheckingFeeType.accept(type)
                } else {
                    let number = input as? Double
                    self.viewModel.currentAmount.accept(number)
                }
            })
            .disposed(by: self.disposeBag)

        // skip initial value so add .skip(1)
        let record = scheduler.record(source: viewModel.getState().debug("🧨").map({ $0?.name }).asObservable().skip(1))
        scheduler.start()
        
        // The expected result count matches the expected count.
        XCTAssert(
            record.events.count == expected.count,
            "The result count(\(record.events.count)) does not match the expected result(\(expected.count))"
        )
        
        // Compare results with expected results.
        let t = record.events.compactMap({ $0.value.element })
        zip(t, expected)
            .enumerated()
            .forEach { (i,element) in
                let (s,e) = element
                XCTAssert(
                    s?.note == e.note ,
                    "Case \(i + 1): \(String(describing: s?.note)) == \(e.note)"
                )
            }
    }
    
    func testInstallmentFee_Bank() {
        
        let scheduler = TestScheduler(initialClock: 0, resolution: 0, simulateProcessingDelay: true)
        
        // Set up all valid conditions to check the validation of a money amount.
        viewModel.currentSelectedShop.accept(.shop1)
        viewModel.currentSelectedShopDomain.accept(Shop.shop1.shopDomains.first)
        
        let events:[String: Any?] = [
            // x represents the action when the request button is pressed.
            "x": (),
            // All keys with the prefix 'b' represent the action when the user select a bank
            "b0": nil,
            "b" : InstallmentBank.stb,
            "b1": InstallmentBank.vib,
            // All keys with prefix 'c' represent the action when the user select installment type
            "c": InstallmentFeeCheckingType.counter,
            "c1": InstallmentFeeCheckingType.online,
            // All keys with the prefix 't' represent the action when the user inputs the money amount.
            "t": Double(5_000_000),
        ]
        
        let setupEvents: [String] = [
            // Case 1: In-store
            "c-t-x-b-x-b1-x-c1-t-x-c",
            // Case 2: Online
            "c1-t-x-b-x"
        ]
        // Set up events and times.
        let scheduleEvents = scheduler.parseEventsAndTimes(
            timeline:  setupEvents.joined(separator: "-") + "--",
            values: events
        ).first!
        
        let expectedCase1: [InstallmentFeeChargeState] = [
            // Select type counter.
            .prepare,
            // money amount is t then press the request button
            .prepare,
            .error(BaseError("bank is required")),
            // select a bank b then press the request button
            .prepare,
            .haveFee,
            // select another bank b1 then press the request button
            .prepare,
            .haveFee,
            // change type to online and input money amount is t
            .prepare,
            // Press the request button
            .prepare,
            .error(BaseError("bank is required")),
            // change type to in-store
            .prepare
        ]
        
        let expectedCase2: [InstallmentFeeChargeState] = [
            // change type to online
            .prepare,
            // input money amount is t then press request button
            .prepare,
            .error(BaseError("bank is required")),
            // select a bank is b then press request button
            .prepare,
            .haveFee
        ]
        
        let expected =
        expectedCase1 +
        expectedCase2
        
        // Observable events timeline.
        scheduler.createHotObservable(scheduleEvents)
            .debug("🔤")
            .subscribe(onNext: {[unowned self] input in
                if input is Void {
                    self.viewModel.getInstallmentFeeCharge()
                } else if let bank = input as? InstallmentBank {
                    self.viewModel.currentSelectedBank.accept(bank)
                } else if let type = input as? InstallmentFeeCheckingType {
                    self.viewModel.installmentCheckingFeeType.accept(type)
                } else {
                    let number = input as? Double
                    self.viewModel.currentAmount.accept(number)
                }
            })
            .disposed(by: self.disposeBag)

        // skip initial value so add .skip(1)
        let record = scheduler.record(source: viewModel.getState().debug("🧨").map({ $0?.name }).asObservable().skip(1))
        scheduler.start()
        
        // The expected result count matches the expected count.
        XCTAssert(
            record.events.count == expected.count,
            "The result count(\(record.events.count)) does not match the expected result(\(expected.count))"
        )
        
        // Compare results with expected results.
        let t = record.events.compactMap({ $0.value.element })
        zip(t, expected)
            .enumerated()
            .forEach { (i,element) in
                let (s,e) = element
                XCTAssert(
                    s?.note == e.note ,
                    "Case \(i + 1): \(String(describing: s?.note)) == \(e.note)"
                )
            }
    }
    
    func testInstallmentFee_CardNumber() {
        
        let scheduler = TestScheduler(initialClock: 0, resolution: 0, simulateProcessingDelay: true)
        
        // Set up all valid conditions to check the validation of a money amount.
        viewModel.installmentCheckingFeeType.accept(.online)
        viewModel.currentSelectedShop.accept(.shop1)
        viewModel.currentSelectedBank.accept(.stb)
        viewModel.banks = [.stb,.vib]
        
        let events:[String: Any?] = [
            // x represents the action when the request button is pressed.
            "x": (),
            // All keys with the prefix 't' represent the action when the user inputs the money amount.
            "t": Double(5_000_000),
            "t1": MONEY_AMOUNT_3503,
            "t2": MONEY_AMOUNT_3506,
            "t3": MONEY_AMOUNT_FOR_CARD_BELONG_TO_ANOTHER_BANK,
            // All keys with the prefix 'n' represent the action when the user input card number
            "n0": String(),
            "n1": "1234",
            "n2": "12345678"
        ]
        
        let setupEvents: [String] = [
            // Case 1: Check validate local only
            "t-x-n1-x-n2-x-n0-x",
            // Case 2: Check simulate throw code from apis
            "n2-t1-x-t2-x-t3-x-t-x"
        ]
        // Set up events and times.
        let scheduleEvents = scheduler.parseEventsAndTimes(
            timeline:  setupEvents.joined(separator: "-") + "--",
            values: events
        ).first!
        
        let expectedCase1: [InstallmentFeeChargeState] = [
            // press the request button with money t and card number is empty
            .prepare,
            .haveFee,
            // input card number is n1 then press the request button
            .prepare,
            .error(BaseError("card number is required the first 8 digits")),
            // input card number is n2 then press the request button
            .prepare,
            .haveFee,
            // delete card number then press the request button
            .prepare,
            .haveFee,
        ]
        
        let expectedCase2: [InstallmentFeeChargeState] = [
            // input card number is n2 and mock data to throw 3503 code then press the request button
            .prepare,
            .error(BaseError("3503")),
            // input mock data throw 3506 then press the request button
            .prepare,
            .error(BaseError("3506")),
            // input mock data when card is belong to the another bank then press the request button
            .prepare,
            .notice(message: "card belong to another bank"),
            // remove mock data then press request button
            .prepare,
            .haveFee
        ]
        
        let expected =
        expectedCase1 +
        expectedCase2
        
        // Observable events timeline.
        scheduler.createHotObservable(scheduleEvents)
            .debug("🔤")
            .subscribe(onNext: {[unowned self] input in
                if input is Void {
                    self.viewModel.getInstallmentFeeCharge()
                } else if let card = input as? String {
                    self.viewModel.cardPrefix.accept(card)
                } else {
                    let number = input as? Double
                    self.viewModel.currentAmount.accept(number)
                }
            })
            .disposed(by: self.disposeBag)

        // skip initial value so add .skip(1)
        let record = scheduler.record(source: viewModel.getState().debug("🧨").map({ $0?.name }).asObservable().skip(1))
        scheduler.start()
        
        // The expected result count matches the expected count.
        XCTAssert(
            record.events.count == expected.count,
            "The result count(\(record.events.count)) does not match the expected result(\(expected.count))"
        )
        
        // Compare results with expected results.
        let t = record.events.compactMap({ $0.value.element })
        zip(t, expected)
            .enumerated()
            .forEach { (i,element) in
                let (s,e) = element
                XCTAssert(
                    s?.note == e.note ,
                    "Case \(i + 1): \(String(describing: s?.note)) == \(e.note)"
                )
            }
    }
    
    func testInstallmentFee_Permission() {
        
        let scheduler = TestScheduler(initialClock: 0, resolution: 0, simulateProcessingDelay: true)
        
        // Set up all valid conditions to check the validation of a money amount.
        viewModel.installmentCheckingFeeType.accept(.counter)
        
        let events:[String: Any?] = [
            // All keys with prefix 'f' is simulate permission.
            "f": Feature.installmentFeeCheck, // represent for have full permissions.
            "f0": Feature.qrCode, // represent for have not permissions both.
            "f1": Feature.installmentFeeCheckOnline, // only permission only
            "f2": Feature.installmentFeeCheckInStore, // in-store permission only
            // All keys with prefix 'c' represent the action when the user select installment type
            "c": InstallmentFeeCheckingType.counter,
            "c1": InstallmentFeeCheckingType.online
        ]
        
        let setupEvents: [String] = [
            "f2-c1-f1-c-f-c1-c-f0-c1-c",
        ]
        // Set up events and times.
        let scheduleEvents = scheduler.parseEventsAndTimes(
            timeline:  setupEvents.joined(separator: "-") + "--",
            values: events
        ).first!
        
        let expected: [InstallmentFeeChargeState] = [
            // simulate in-store permission only then change to tab online
            .haveNoPermission,
            // simulate online permission only then change to tab in-store
            .haveNoPermission,
            // simulate have permissions both then switch to tab online and in-store
            .prepare,
            .prepare,
            // simulate have not permissions both then switch to tab online and in-store
            .haveNoPermission,
            .haveNoPermission
        ]
        
        // Observable events timeline.
        scheduler.createHotObservable(scheduleEvents)
            .debug("🔤")
            .subscribe(onNext: {[unowned self] input in
                if let type = input as? InstallmentFeeCheckingType {
                    self.viewModel.installmentCheckingFeeType.accept(type)
                } else if let feature = input as? Feature {
                    if feature == .installmentFeeCheck {
                        self.userDefaultMock.permission = [.installmentFeeCheckOnline, .installmentFeeCheckInStore]
                    } else {
                        self.userDefaultMock.permission = [feature]
                    }
                }
            })
            .disposed(by: self.disposeBag)

        // skip initial value so add .skip(1)
        let record = scheduler.record(source: viewModel.getState().debug("🧨").map({ $0?.name }).asObservable().skip(1))
        scheduler.start()
        
        // The expected result count matches the expected count.
        XCTAssert(
            record.events.count == expected.count,
            "The result count(\(record.events.count)) does not match the expected result(\(expected.count))"
        )
        
        // Compare results with expected results.
        let t = record.events.compactMap({ $0.value.element })
        zip(t, expected)
            .enumerated()
            .forEach { (i,element) in
                let (s,e) = element
                XCTAssert(
                    s?.note == e.note ,
                    "Case \(i + 1): \(String(describing: s?.note)) == \(e.note)"
                )
            }
    }
    
    func testInstallmentFee_testGetFeeChargeResult() {
        
        let inputs: [
        (
            type: InstallmentFeeCheckingType,
            money: Double?,
            card: String?,
            period: [Int],
            shop: Shop?,
            shopDomain: String?,
            bank: InstallmentBank?
        )
        ] = [
            (type: .online, money: MONEY_AMOUNT_3501, card: nil, period: [3], shop: .shop1, shopDomain: Shop.shop1.shopDomains.first, bank: .stb), // case 1
            (type: .online, money: MONEY_AMOUNT_3502, card: nil, period: [3], shop: .shop1, shopDomain: Shop.shop1.shopDomains.first, bank: .stb), // case 2
            (type: .online, money: MONEY_AMOUNT_3503, card: nil, period: [3], shop: .shop1, shopDomain: Shop.shop1.shopDomains.first, bank: .stb), // case 3
            (type: .online, money: MONEY_AMOUNT_3504, card: nil, period: [3], shop: .shop1, shopDomain: Shop.shop1.shopDomains.first, bank: .stb), // case 4
            (type: .online, money: MONEY_AMOUNT_3505, card: nil, period: [3], shop: .shop1, shopDomain: Shop.shop1.shopDomains.first, bank: .stb), // case 5
            (type: .online, money: MONEY_AMOUNT_3506, card: nil, period: [3], shop: .shop1, shopDomain: Shop.shop1.shopDomains.first, bank: .stb), // case 6
            (type: .online, money: MONEY_AMOUNT_3507, card: nil, period: [3], shop: .shop1, shopDomain: Shop.shop1.shopDomains.first, bank: .stb), // case 7
            (type: .online, money: MONEY_AMOUNT_FOR_ERROR_1, card: nil, period: [3], shop: .shop1, shopDomain: Shop.shop1.shopDomains.first, bank: .stb), // case 8
            (type: .online, money: MONEY_AMOUNT_FOR_CARD_BELONG_TO_ANOTHER_BANK, card: nil, period: [3], shop: .shop1, shopDomain: Shop.shop1.shopDomains.first, bank: .stb) // case 9
        ]
        
        let expectedState:[(Bool, BaseError?)] = [
            (false,InstallmentFeeCardError(BaseError())), // case 1
            (false,InstallmentFeeRequireConversationFeeError(installmentFeesCharge: [], BaseError())), // case 2
            (false,InstallmentFeeCardError(BaseError())),// case 3
            (false,InstallmentFeeMoneyBelowMinOrAboveMaxError("")),// case 4
            (false,InstallmentFeeMoneyBelowMinOrAboveMaxError("")),// case 5
            (false,InstallmentFeeCardError("")),// case 6
            (false,InstallmentFeeSupportPeriodError("")),// case 7
            (false,BaseError("")),// case 8
            (true,nil),// case 9
        ]
        
        let scheduler = TestScheduler(initialClock: 0, resolution: 0.2, simulateProcessingDelay: true)
        
        let inputCase = scheduler.parseEventsAndTimes(timeline: inputs.compactMap{_ in "--x" }.joined(), values: events).first!
        
        var recordInputs: [(type: InstallmentFeeCheckingType,
                            money: Double?,
                            card: String?,
                            period: [Int],
                            shop: Domain.Shop?,
                            shopDomain: String?,
                            bank: InstallmentBank?)] = []
        
        var inputCaseIndex = 0
        let result = scheduler.createHotObservable(inputCase).asObservable()
            .flatMap {[unowned self] _ in
                let (type, money, card, period, shop, shopDomain, bank) = inputs[inputCaseIndex]
                recordInputs.append((type, money, card, period, shop, shopDomain, bank))
                inputCaseIndex += 1
                return self.getFeeCharge(type: type, amount: money ?? 0, bankCode: bank?.bankCode ?? "", cardNoPrefix: card, periods: period, installmentConversionFee: self.viewModel.conversationFee.value, shopId: shop?.shopId, shopDomain: shopDomain)
            }
            .map { result -> (Bool, BaseError?) in
                switch result {
                case .success(let result):
                    return (true, nil)
                case .failure(let error):
                    return (false, error)
                }
            }
        
        let recordsObserver = scheduler.record(source: result.asObservable())
        
        scheduler.start()
        let records = recordsObserver.events.compactMap({$0.value.element})
        zip(records, zip(expectedState, recordInputs))
            .forEach { (result, local) in
                let expect = local.0
                let recordInputs = local.1
                let (type, money, card, period, shop, shopDomain, bank) = recordInputs
                XCTAssert(result.0 == expect.0 && result.1.debugDescription == expect.1.debugDescription, "\(String(describing: result)) == \(String(describing: expect)) with inputs:\ntype: \(type), money: \(String(describing: money)), card: \(String(describing: card)), period: \(period), shop: \(String(describing: shop)), domain: \(String(describing: shopDomain)), bank: \(String(describing: bank?.bankCode))-\(String(describing: bank?.periodSupports.compactMap({$0.debugDescription}).joined(separator: "|")))")
            }
    }
}

// MARK: -  Private function
private extension InstallmentFee_VMTests {
    
    func getFeeCharge(
        type: InstallmentFeeCheckingType,
        amount: Double,
        bankCode: String,
        cardNoPrefix: String?,
        periods: [Int],
        installmentConversionFee: String?,
        shopId: Double?,
        shopDomain: String?
    ) -> Observable<Result<[InstallmentFeeCharge],BaseError>> {
        Observable.create {[weak self] ob in
            guard let self else {
                ob.onCompleted()
                return Disposables.create()
            }
            self.viewModel.feeUC.getInstallmentFeeCharge(type: type, amount: amount, bankCode: bankCode, cardNoPrefix: cardNoPrefix, periods: periods, installmentConversionFee: installmentConversionFee, shopId: shopId, shopDomain: shopDomain)
                .asObservable()
                .subscribe(onNext: {
                    ob.onNext(.success($0))
                }, onError: { error in
                    if let error = error as? BaseError {
                        ob.onNext(.failure(error))
                    } else {
                        ob.onCompleted()
                    }
                })
                .disposed(by: self.disposeBag)
            return Disposables.create()
        }
    }
    
    func validate(
        type: InstallmentFeeCheckingType,
        money: Double?,
        card: String?,
        period: [Int],
        shop: Domain.Shop?,
        shopDomain: String?,
        bank: InstallmentBank?
    ) -> Observable<Result<Void, Error>>{
        let data: InstallmentFeeChargeUseCase.DataChainGetBanksResponse = (
            [],[], shop, shopDomain, bank, type, money, card, period, nil // conversationFee
        )
        return Observable.create {[unowned self] ob in
            self.viewModel.feeUC.validate(data)
                .asObservable()
                .subscribe { _ in
                    ob.onNext(.success(()))
                } onError: { error in
                    ob.onNext(.failure(error))
                }
                .disposed(by: self.disposeBag)
            return Disposables.create()
        }
    }
}

extension Domain.PeriodSupport {
    public var debugDescription: String {
        return "period: \(period) - min: \(minPayment) - max: \(maxPayment)"
    }
    
    static var three: Domain.PeriodSupport {
        .init(period: 3, maxPayment: 1_000_000_000, minPayment: 3_000_000)
    }
    static var six: Domain.PeriodSupport {
        .init(period: 6, maxPayment: 1_000_000_000, minPayment: 3_000_000)
    }
    static var nine: Domain.PeriodSupport {
        .init(period: 9, maxPayment: 1_000_000_000, minPayment: 3_000_000)
    }
    static var thirtySix: Domain.PeriodSupport {
        .init(period: 36, maxPayment: 1_000_000_000, minPayment: 3_000_000)
    }
}

extension InstallmentBank {
    static var stb: InstallmentBank {
        .init(bankCode: "STB", bankName: "Sacombank", periodSupports: [.three, .six, .nine, .thirtySix], bankLogoUrl: "")
    }
    
    static var vib: InstallmentBank {
        .init(bankCode: "VIB", bankName: "VietInbank", periodSupports: [.three, .six, .nine], bankLogoUrl: "")
    }
}

extension Domain.Shop {
    static var shop1: Domain.Shop {
        .init(shopId: 100, shopDomains: ["https://shops1.com.vn"], emailShop: nil, shopName: "Shop one")
    }
    static var shop2: Domain.Shop {
        .init(shopId: 200, shopDomains: ["https://shops2.com.vn"], emailShop: nil, shopName: "Shop two")
    }
}

extension InstallmentFeeChargeState: Equatable {
    public static func == (lhs: PayooMerchant.InstallmentFeeChargeState, rhs: PayooMerchant.InstallmentFeeChargeState) -> Bool {
        lhs.note == rhs.note
    }
    
    public var note: String {
        switch self {
        case .prepare:
            "prepare"
        case .haveNoPermission:
            "haveNoPermission"
        case .noFee:
            "noFee"
        case .notice(message: let message):
            "notice"
        case .haveFee:
            "haveFee"
        case .error(_):
            "error"
        }
    }
}
