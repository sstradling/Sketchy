//
//  OperationSet.swift
//  RoughSwift
//
//  Created by khoa on 19/03/2019.
//  Copyright © 2019 Khoa Pham. All rights reserved.
//

import Foundation

/// Instructions about which set type to draw and operations
public struct OperationSet {
    public let type: OperationSetType
    public let operations: [Operation]
    
    // For path
    public let path: String?
    public let size: Size?

    /// Multiplier on the fill line width for this set.
    ///
    /// Contour falloff groups strokes into bands and stores the band's scale
    /// here. `nil` draws at the normal fill weight.
    public let fillLineScale: Float?

    /// Absolute fill-stroke width in points. When set, it replaces `fillWeight * fillLineScale`.
    ///
    /// Wash passes store each stroke's width here so a 42-point crayon stroke is not
    /// a multiplier on the outline weight.
    public let fillLineWidth: Float?

    /// Multiplier on the fill opacity for this set. Wash passes vary it per stroke.
    public let opacityScale: Float?

    public init(
        type: OperationSetType,
        operations: [Operation],
        path: String?,
        size: Size?,
        fillLineScale: Float? = nil,
        fillLineWidth: Float? = nil,
        opacityScale: Float? = nil
    ) {
        self.type = type
        self.operations = operations
        self.path = path
        self.size = size
        self.fillLineScale = fillLineScale
        self.fillLineWidth = fillLineWidth
        self.opacityScale = opacityScale
    }

    static func from(dictionary: JSONDictionary) -> OperationSet? {
        guard
            let rawType = dictionary["type"] as? String,
            let type = OperationSetType(rawValue: rawType),
            let ops = dictionary["ops"] as? JSONArray
        else {
            return nil
        }

        let path = dictionary["path"] as? String
        var size: Size? = nil
        if let sizeArray = dictionary["size"] as? [NSNumber], sizeArray.count == 2{
            size = Size(width: sizeArray[0].floatValue, height: sizeArray[1].floatValue)
        }

        return OperationSet(
            type: type,
            operations: ops.compactMap({ Operation.from(dictionary: $0) }),
            path: path,
            size: size
        )
    }
}
