import Foundation

/// Builders for DynamicLake's JSON components, so the presenter reads like the layout it makes.
enum C {
    static func text(_ text: String, id: String? = nil, style: String? = nil, weight: String? = nil, tint: String? = nil) -> JSON {
        // DynamicLake rejects empty text, so an empty string becomes a thin space.
        var object: [String: JSON] = ["type": "text", "text": .string(text.isEmpty ? "\u{2009}" : text)]
        object["id"] = id.map(JSON.string)
        object["style"] = style.map(JSON.string)
        object["weight"] = weight.map(JSON.string)
        object["tint"] = tint.map(JSON.string)
        return .object(object)
    }

    static func symbol(_ name: String, id: String? = nil, tint: String? = nil, size: Int? = nil) -> JSON {
        var object: [String: JSON] = ["type": "image", "source": "sfSymbol", "systemImage": .string(name)]
        object["id"] = id.map(JSON.string)
        object["tint"] = tint.map(JSON.string)
        object["size"] = size.map { .number(Double($0)) }
        return .object(object)
    }

    static func asset(_ assetID: String, id: String? = nil, size: Int? = nil, actionID: String? = nil, title: String? = nil) -> JSON {
        var object: [String: JSON] = ["type": "image", "source": "asset", "assetID": .string(assetID)]
        object["id"] = id.map(JSON.string)
        object["size"] = size.map { .number(Double($0)) }
        object["actionID"] = actionID.map(JSON.string)
        object["title"] = title.map(JSON.string)
        return .object(object)
    }

    static func button(_ actionID: String, symbol: String? = nil, title: String? = nil, id: String? = nil,
                       shape: String? = nil, role: String? = nil, tint: String? = nil, size: Int? = nil) -> JSON {
        var object: [String: JSON] = ["type": "button", "actionID": .string(actionID)]
        object["systemImage"] = symbol.map(JSON.string)
        object["title"] = title.map(JSON.string)
        object["id"] = id.map(JSON.string)
        object["shape"] = shape.map(JSON.string)
        object["role"] = role.map(JSON.string)
        object["tint"] = tint.map(JSON.string)
        object["size"] = size.map { .number(Double($0)) }
        return .object(object)
    }

    static func status(_ status: String, tint: String, size: Int? = nil) -> JSON {
        var object: [String: JSON] = ["type": "status", "status": .string(status), "tint": .string(tint)]
        object["size"] = size.map { .number(Double($0)) }
        return .object(object)
    }

    static func progress(_ value: Double? = nil, tint: String) -> JSON {
        var object: [String: JSON] = ["type": "progress", "tint": .string(tint)]
        object["value"] = value.map(JSON.number)
        return .object(object)
    }

    static func timer(from start: Date, to end: Date, countsDown: Bool = true, id: String? = nil, tint: String? = nil) -> JSON {
        var object: [String: JSON] = [
            "type": "timer",
            "startDate": .string(iso(start)),
            "endDate": .string(iso(end)),
        ]
        if !countsDown { object["countsDown"] = false }
        object["id"] = id.map(JSON.string)
        object["tint"] = tint.map(JSON.string)
        return .object(object)
    }

    static func hstack(_ children: [JSON], spacing: Int? = nil, alignment: String? = nil, id: String? = nil,
                       padding: JSON? = nil, contextMenu: [JSON]? = nil, drag: JSON? = nil) -> JSON {
        stack("hstack", children, spacing: spacing, alignment: alignment, id: id, padding: padding, contextMenu: contextMenu, drag: drag)
    }

    static func vstack(_ children: [JSON], spacing: Int? = nil, alignment: String? = nil, id: String? = nil,
                       padding: JSON? = nil, contextMenu: [JSON]? = nil, drag: JSON? = nil) -> JSON {
        stack("vstack", children, spacing: spacing, alignment: alignment, id: id, padding: padding, contextMenu: contextMenu, drag: drag)
    }

    static func scroll(_ children: [JSON], spacing: Int? = nil, softFade: String = "both") -> JSON {
        var object: [String: JSON] = ["type": "scroll", "children": .array(children), "softFade": .string(softFade)]
        object["spacing"] = spacing.map { .number(Double($0)) }
        return .object(object)
    }

    static func spacer(_ length: Int? = nil) -> JSON {
        var object: [String: JSON] = ["type": "spacer"]
        object["length"] = length.map { .number(Double($0)) }
        return .object(object)
    }

    static func menuItem(_ title: String, symbol: String, actionID: String, destructive: Bool = false) -> JSON {
        var object: [String: JSON] = ["title": .string(title), "systemImage": .string(symbol), "actionID": .string(actionID)]
        if destructive { object["role"] = "destructive" }
        return .object(object)
    }

    private static func stack(_ type: String, _ children: [JSON], spacing: Int?, alignment: String?, id: String?,
                              padding: JSON?, contextMenu: [JSON]?, drag: JSON?) -> JSON {
        var object: [String: JSON] = ["type": .string(type), "children": .array(children)]
        object["spacing"] = spacing.map { .number(Double($0)) }
        object["alignment"] = alignment.map(JSON.string)
        object["id"] = id.map(JSON.string)
        object["padding"] = padding
        object["contextMenu"] = contextMenu.map(JSON.array)
        object["drag"] = drag
        return .object(object)
    }

    private static func iso(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
