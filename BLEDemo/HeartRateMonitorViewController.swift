//
//  HeartRateMonitorViewController.swift
//  BLEDemo
//
//  Created by Kirti Parghi on 6/26/19.
//  Copyright © 2019 Kirti Parghi. All rights reserved.
//

import UIKit
import CoreBluetooth

//Core Bluetooth service IDs
let BLE_Heart_Rate_Service_CBUUID = CBUUID(string: "0x180D")

//Core Bluetooth characteristic IDs
let BLE_Heart_Rate_Measurement_Characteristic_CBUUID = CBUUID(string: "0x2A37")

//this class adopts both the central and peripheral delegates and therefore must conform to these protocols requirements
class HeartRateMonitorViewController: UIViewController, CBCentralManagerDelegate, CBPeripheralDelegate {
    
    //create instance variables of the CBCentralManager and CBPeripheral so they persist for the duration of the app's life
    var centralManager: CBCentralManager?
    var peripheralHeartRateMonitor: CBPeripheral?
    
    @IBOutlet weak var brandNameTextField: UITextField!
    @IBOutlet weak var beatsPerMinuteLabel: UILabel!
    
    // MARK: - UIViewController delegate
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // initially, we're scanning and not connected
        brandNameTextField.text = "----"
        beatsPerMinuteLabel.text = "---"
        
        //create a concurrent background queue for the central
        let centralQueue: DispatchQueue = DispatchQueue(label: "com.kirti.BLEDemo.centralQueueName", attributes: .concurrent)
        //create a central to scan for, connect to,
        // manage, and collect data from peripherals
        centralManager = CBCentralManager(delegate: self, queue: centralQueue)
    }
    
    //CBCentralManagerDelegate methods

    // this method is called based on
    // the device's Bluetooth state; we can ONLY
    // scan for peripherals if Bluetooth is .poweredOn
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        
        switch central.state {
        
        case .unknown:
            print("Bluetooth status is UNKNOWN")
        case .resetting:
            print("Bluetooth status is RESETTING")
        case .unsupported:
            print("Bluetooth status is UNSUPPORTED")
        case .unauthorized:
            print("Bluetooth status is UNAUTHORIZED")
        case .poweredOff:
            print("Bluetooth status is POWERED OFF")
        case .poweredOn:
            print("Bluetooth status is POWERED ON")
            // STEP 3.2: scan for peripherals that we're interested in
            centralManager?.scanForPeripherals(withServices: [BLE_Heart_Rate_Service_CBUUID])
            
        @unknown default: break
        }
    }
    
    // discover what peripheral devices OF INTEREST
    // are available for this app to connect to
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        print(peripheral.name!)
        decodePeripheralState(peripheralState: peripheral.state)
        // MUST store a reference to the peripheral in
        // class instance variable
        peripheralHeartRateMonitor = peripheral
        // since HeartRateMonitorViewController
        // adopts the CBPeripheralDelegate protocol,
        // the peripheralHeartRateMonitor must set its
        // delegate property to HeartRateMonitorViewController
        // (self)
        peripheralHeartRateMonitor?.delegate = self
        
        // stop scanning to preserve battery life;
        // re-scan if disconnected
        centralManager?.stopScan()
        
        // connect to the discovered peripheral of interest
        centralManager?.connect(peripheralHeartRateMonitor!)
    }
    
    // "Invoked when a connection is successfully created with a peripheral."
    // we can only move forwards when we know the connection
    // to the peripheral succeeded
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        DispatchQueue.main.async { () -> Void in
            self.brandNameTextField.text = peripheral.name!
            self.beatsPerMinuteLabel.text = "---"
        }
        //look for services of interest on peripheral
        peripheralHeartRateMonitor?.discoverServices([BLE_Heart_Rate_Service_CBUUID])
    }
    
    // when a peripheral disconnects, take
    // use-case-appropriate action
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        // print("Disconnected!")
        DispatchQueue.main.async { () -> Void in
            self.brandNameTextField.text = "----"
            self.beatsPerMinuteLabel.text = "---"
        }
        
        //in this use-case, start scanning
        // for the same peripheral or another, as long
        // as they're HRMs, to come back online
        centralManager?.scanForPeripherals(withServices: [BLE_Heart_Rate_Service_CBUUID])
    }

    // MARK: - CBPeripheralDelegate methods
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        for service in peripheral.services! {
            if service.uuid == BLE_Heart_Rate_Service_CBUUID {
                print("Service: \(service)")
                // look for characteristics of interest
                // within services of interest
                peripheral.discoverCharacteristics(nil, for: service)
            }
        }
    }
    
    // confirm we've discovered characteristics
    // of interest within services of interest
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for characteristic in service.characteristics! {
            print(characteristic)
            if characteristic.uuid == BLE_Heart_Rate_Measurement_Characteristic_CBUUID {
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }
    
    // we're notified whenever a characteristic
    // value updates regularly or posts once; read and
    // decipher the characteristic value(s) that we've
    // subscribed to
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        
        if characteristic.uuid == BLE_Heart_Rate_Measurement_Characteristic_CBUUID {
            // we generally have to decode BLE
            // data into human readable format
            let heartRate = deriveBeatsPerMinute(using: characteristic)
            
            DispatchQueue.main.async { () -> Void in
                
                UIView.animate(withDuration: 1.0, animations: {
                    self.beatsPerMinuteLabel.alpha = 1.0
                    self.beatsPerMinuteLabel.text = String(heartRate)
                }, completion: { (true) in
                    self.beatsPerMinuteLabel.alpha = 0.0
                })
            }
        }
    }
    
    //Utilities
    func deriveBeatsPerMinute(using heartRateMeasurementCharacteristic: CBCharacteristic) -> Int {
        let heartRateValue = heartRateMeasurementCharacteristic.value!
        // convert to an array of unsigned 8-bit integers
        let buffer = [UInt8](heartRateValue)

        // UInt8: "An 8-bit unsigned integer value type."
        // the first byte (8 bits) in the buffer is flags
        // (meta data governing the rest of the packet);
        // if the least significant bit (LSB) is 0,
        // the heart rate (bpm) is UInt8, if LSB is 1, BPM is UInt16
        if ((buffer[0] & 0x01) == 0) {
            // second byte: "Heart Rate Value Format is set to UINT8."
            print("BPM is UInt8")
            return Int(buffer[1])
        } else { // I've never seen this use case, so I'll
                 // leave it to theoroticians to argue
            // 2nd and 3rd bytes: "Heart Rate Value Format is set to UINT16."
            print("BPM is UInt16")
            return -1
        }
    }
    
    func decodePeripheralState(peripheralState: CBPeripheralState) {
        switch peripheralState {
            case .disconnected:
                print("Peripheral state: disconnected")
            case .connected:
                print("Peripheral state: connected")
            case .connecting:
                print("Peripheral state: connecting")
            case .disconnecting:
                print("Peripheral state: disconnecting")
            @unknown default: break
        }
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }
}
