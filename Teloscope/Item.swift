//
//  Item.swift
//  Teloscope
//
//  Created by mtgto on 2026/04/14.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
