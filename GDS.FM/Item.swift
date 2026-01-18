//
//  Item.swift
//  GDS.FM
//
//  Created by Jorge on 18.01.2026.
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
