//
//  ViewController.swift
//  GeoKiyo
//
//  Created by Kiyoshi Amano on 2021/06/25.
//

import UIKit

class ViewController: UIViewController {
    
    
    @IBOutlet weak var trackViewButton: UIButton!
    @IBOutlet weak var tarckEventButton: UIButton!
    @IBOutlet weak var traceIdText: UITextField!
    @IBOutlet weak var startTraceButton: UIButton!
    @IBOutlet weak var stopTraceButton: UIButton!
    @IBOutlet weak var simulateGeoButton: UIButton!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        
        navigationItem.title = "TealiumSwiftExample"
        
        // ボタンを装飾
        decorateButton(trackViewButton)
        decorateButton(tarckEventButton)
        decorateButton(startTraceButton)
        decorateButton(stopTraceButton)
        decorateButton(simulateGeoButton)
    }
    
    func decorateButton(_ button: UIButton) {
        //let rgba = UIColor(red: 255/255, green: 128/255, blue: 168/255, alpha: 1.0) // ボタン背景色設定
        //button.backgroundColor = rgba                                               // 背景色
        button.layer.borderWidth = 0.5                                              // 枠線の幅
        button.layer.borderColor = UIColor.systemPurple.cgColor                     // 枠線の色
        button.layer.cornerRadius = 5.0                                             // 角丸のサイズ
        //button.setTitleColor(UIColor.white, for: UIControlState.normal)             // タイトルの色
    }
    
    @IBAction func trackView(_ sender: Any) {
    }
    
    @IBAction func trackEvent(_ sender: Any) {
    }
    
    @IBAction func startTrace(_ sender: Any) {
    }
    
    @IBAction func leaveTrace(_ sender: Any) {
    }
    
    @IBAction func simulateGeofence(_ sender: Any) {
        guard let myAppUrl = URL(string: "tealiumGeoSimulator://?source=geokiyo") else {return}
        UIApplication.shared.openURL(myAppUrl)
    }
    
    
}

