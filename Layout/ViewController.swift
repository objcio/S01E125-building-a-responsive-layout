//
//  ViewController.swift
//  LabelLayout
//
//  Created by Chris Eidhof on 23.08.18.
//  Copyright © 2018 objc.io. All rights reserved.
//

import UIKit

extension UIView {
    func setSubviews<S: Sequence>(_ other: S) where S.Element == UIView {
        let views = Set(other)
        let sub = Set(subviews)
        for v in sub.subtracting(views) {
            v.removeFromSuperview()
        }
        for v in views.subtracting(sub) {
            addSubview(v)
        }
    }
}

extension UILabel {
    convenience init(text: String, size: UIFont.TextStyle, multiline: Bool = false, textColor: UIColor = .black) {
        self.init()
        font = UIFont.preferredFont(forTextStyle: size)
        self.text = text
        self.textColor = textColor
        adjustsFontForContentSizeCategory = true
        if multiline {
            numberOfLines = 0
        }
    }
}

extension UIView {
    convenience init(backgroundColor: UIColor, cornerRadius: CGFloat = 0) {
        self.init()
        self.backgroundColor = backgroundColor
        self.layer.cornerRadius = cornerRadius
    }
}


enum Width: Equatable {
    case absolute(CGFloat)
    case flexible(min: CGFloat)
    case basedOnContents
    
    var min: CGFloat {
        switch self {
        case let .absolute(x): return x
        case let .flexible(min: x): return x
        case .basedOnContents: return 0 // todo log a warning (or better: refactor our enum)
        }
    }
    
    var isFlexible: Bool {
        switch self {
        case .absolute: return false
        case .flexible: return true
        case .basedOnContents: return false
        }
    }
}

indirect enum Layout {
    case view(UIView, Layout)
    case space(Width, Layout)
    case box(contents: Layout, Width, wrapper: UIView?, Layout)
    case newline(space: CGFloat, Layout)
    case choice(Layout, Layout)
    case empty
}

extension Layout {
    func apply(containerWidth: CGFloat) -> [UIView] {
        let lines = computeLines(containerWidth: containerWidth, currentX: 0)
        return lines.apply(containerWidth: containerWidth, startAt: .zero)
    }
}

extension Array where Element == Line {
    func apply(containerWidth: CGFloat, startAt: CGPoint) -> [UIView] {
        var origin = startAt
        var result: [UIView] = []
        for line in self {
            origin.x = startAt.x
            origin.y += line.space
            let availableSpace = containerWidth - line.minWidth
            let flexibleSpace = availableSpace / CGFloat(line.numberOfFlexibleSpaces)
            var lineHeight: CGFloat = 0
            for element in line.elements {
                switch element {
                case let .box(contents, _, nil):
                    let width = element.absoluteWidth(flexibleSpace: flexibleSpace)
                    let views = contents.apply(containerWidth: width, startAt: origin)
                    origin.x += width
                    let height = (views.map { $0.frame.maxY }.max() ?? origin.y) - origin.y
                    lineHeight = Swift.max(lineHeight, height)
                    result.append(contentsOf: views)
                case let .box(contents, _, wrapper?):
                    let width = element.absoluteWidth(flexibleSpace: flexibleSpace)
                    let margins = wrapper.layoutMargins.left + wrapper.layoutMargins.right
                    let start = CGPoint(x: wrapper.layoutMargins.left, y: wrapper.layoutMargins.top)
                    let subviews = contents.apply(containerWidth: width - margins, startAt: start)
                    wrapper.setSubviews(subviews)
                    let contentMaxY = subviews.map { $0.frame.maxY }.max() ?? wrapper.layoutMargins.top
                    let size = CGSize(width: width, height: contentMaxY + wrapper.layoutMargins.bottom)
                    wrapper.frame = CGRect(origin: origin, size: size)

                    origin.x += size.width
                    lineHeight = Swift.max(lineHeight, size.height)
                    result.append(wrapper)
                case .space(_):
                    origin.x += element.absoluteWidth(flexibleSpace: flexibleSpace)
                case let .view(v, size):
                    result.append(v)
                    v.frame = CGRect(origin: origin, size: size)
                    origin.x += size.width
                    lineHeight = Swift.max(lineHeight, size.height)
                }
            }
            origin.y += lineHeight
        }
        return result
    }
}

struct Line {
    enum Element {
        case view(UIView, CGSize)
        case space(Width)
        case box([Line], Width, wrapper: UIView?)
    }
    
    var elements: [Element]
    var space: CGFloat
    
    var minWidth: CGFloat {
        return elements.reduce(0) { $0 + $1.minWidth }
    }
    
    var numberOfFlexibleSpaces: Int {
        return elements.filter { $0.isFlexible }.count
    }
}

extension Line.Element {
    var isFlexible: Bool {
        switch self {
        case .view: return false
        case let .box(_, w, _): return w.isFlexible
        case let .space(width): return width.isFlexible
        }
    }
    
    var minWidth: CGFloat {
        switch self {
        case let .view(_, size): return size.width
        case let .box(lines, w, wrapper):
            guard w == .basedOnContents else { return w.min }
            let margins = (wrapper?.layoutMargins).map { $0.left + $0.right } ?? 0
            return (lines.map { $0.minWidth }.max() ?? 0) + margins
        case let .space(width): return width.min
        }
    }
}

extension Line.Element {
    var width: Width {
        switch self {
        case let .view(_, size): return .absolute(size.width)
        case let .space(w): return w
        case let .box(_, w, _): return w
        }
    }
        
    func absoluteWidth(flexibleSpace: CGFloat) -> CGFloat {
        switch width {
        case let .absolute(w): return w
        case let .flexible(min): return min + flexibleSpace
        case .basedOnContents: return minWidth
        }
    }
}
    

extension Layout {
    func computeLines(containerWidth: CGFloat, currentX: CGFloat) -> [Line] {
        var x = currentX
        var current: Layout = self
        var lines: [Line] = []
        var line: Line = Line(elements: [], space: 0)
        while true {
            switch current {
            case let .view(v, rest):
                let availableWidth = containerWidth - x
                let size = v.sizeThatFits(CGSize(width: availableWidth, height: .greatestFiniteMagnitude))
                x += size.width
                line.elements.append(.view(v, size))
                //if x >= containerWidth { return false }
                current = rest
            case let .space(width, rest):
                x += width.min
                //if x >= containerWidth { return false }
                line.elements.append(.space(width))
                current = rest
            case let .box(contents, width, wrapper, rest):
                let margins = (wrapper?.layoutMargins).map { $0.left + $0.right } ?? 0
                let availableWidth = containerWidth - x - margins
                let lines = contents.computeLines(containerWidth: availableWidth, currentX: x)
                let result = Line.Element.box(lines, width, wrapper: wrapper)
                x += result.minWidth
                line.elements.append(result)
                current = rest
            case let .newline(space, rest):
                x = 0
                lines.append(line)
                line = Line(elements: [], space: space)
                current = rest
            case let .choice(first, second):
                var firstLines = first.computeLines(containerWidth: containerWidth, currentX: x)
                firstLines[0].elements.insert(contentsOf: line.elements, at: 0)
                firstLines[0].space += line.space
                let tooWide = firstLines.contains { $0.minWidth >= containerWidth }
                if tooWide {
                    current = second
                } else {
                    return lines + firstLines
                }
            case .empty:
                lines.append(line)
                return lines
            }
        }

    }
}


final class LayoutContainer: UIView {
    private let _layout: Layout
    init(_ layout: Layout) {
        self._layout = layout
        super.init(frame: .zero)
        
        NotificationCenter.default.addObserver(self, selector: #selector(setNeedsLayout), name: UIContentSizeCategory.didChangeNotification, object: nil)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        let views = _layout.apply(containerWidth: bounds.width)
        setSubviews(views)
    }
}

extension BidirectionalCollection where Element == Layout {
    func horizontal(space: Width? = nil) -> Layout {
        guard var result = last else { return .empty }
        for l in dropLast().reversed() {
            if let width = space {
                result = .space(width, result)
            }
            result = l + result
        }
        return result
    }
    
    func vertical(space: CGFloat = 0) -> Layout {
        guard var result = last else { return .empty }
        for l in dropLast().reversed() {
            result = l + .newline(space: space, result)
        }
        return result
    }
}

func +(lhs: Layout, rhs: Layout) -> Layout {
    switch lhs {
    case let .view(v, remainder):
        return .view(v, remainder+rhs)
    case let .box(contents, width, wrapper, remainder):
        return .box(contents: contents, width, wrapper: wrapper, remainder + rhs)
    case let .space(w, r):
        return .space(w, r + rhs)
    case let .newline(space, r):
        return .newline(space: space, r + rhs)
    case let .choice(l, r):
        return .choice(l + rhs, r + rhs)
    case .empty:
        return rhs
    }
}

extension UIView {
    var layout: Layout {
        return .view(self, .empty)
    }
}

extension Layout {
    func or(_ other: Layout) -> Layout {
        return .choice(self, other)
    }
    
    func box(wrapper: UIView? = nil, width: Width = .basedOnContents) -> Layout {
        return .box(contents: self, width, wrapper: wrapper, .empty)
    }
}


struct Airport {
    var city: String
    var code: String
    var time: Date
}

struct Flight {
    var origin: Airport
    var destination: Airport
    var name: String
    var terminal: String
    var gate: String
    var boarding: Date
}

let start: TimeInterval = 3600*7
let flight = Flight(origin: Airport(city: "Berlin", code: "TXL", time:
    Date(timeIntervalSince1970: start)), destination: Airport(city: "Paris", code: "CDG", time: Date(timeIntervalSince1970: start + 2*3600)), name: "AF123", terminal: "1", gate: "14", boarding: Date(timeIntervalSince1970: start - 1800))

let formatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .none
    f.timeStyle = .short
    return f
}()

extension Flight {
    var metaData: [(String, String)] {
        return [("FLIGHT", name), ("TERMINAL", terminal), ("GATE", gate), ("BOARDING", formatter.string(from: boarding))]
    }
}

extension Layout {
    var centered: Layout {
        return [.space(.flexible(min: 0), .empty), self, .space(.flexible(min: 0), .empty)].horizontal()
    }
}

extension Airport {
    func layout(title: String) -> Layout {
        let l = UILabel(text: title, size: .body, textColor: .white).layout.centered
        let c = UILabel(text: code, size: .largeTitle, textColor: .white).layout.centered
        let t = UILabel(text: formatter.string(from: time), size: .body, textColor: .white).layout.centered
        return [l, c, t].vertical().box()

    }
}

extension Flight {
    var layout: Layout {
        let orig = origin.layout(title: "From")
        let dest = destination.layout(title: "To")
        let flightBg = UIView(backgroundColor: .gray, cornerRadius: 10)
        let flight = [orig, dest].horizontal(space: .flexible(min: 20)).or([orig.centered, dest.centered].vertical(space: 10)).box(wrapper: flightBg, width: .flexible(min: 0))
        let metaItems = metaData.map { (key, value) in
            [
                UILabel(text: key, size: .caption1, textColor: .white).layout,
                UILabel(text: value, size: .body, textColor: .white).layout
            ].vertical(space: 0).box()
        }
        let meta = metaItems.horizontal(space: .flexible(min: 20)).or(
            [
                metaItems[0...1].horizontal(space: .flexible(min: 20)),
                metaItems[2...3].horizontal(space: .flexible(min: 20))
            ].vertical(space: 10)
        ).or(metaItems.vertical(space: 10))
        let metaLayout = meta.box(wrapper: UIView(backgroundColor: .red, cornerRadius: 10), width: .flexible(min: 0))
        return [flight, metaLayout].vertical(space: 20)
    }
}

class ViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        let layout = flight.layout
        
        let container = LayoutContainer(layout)
        container.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(container)
        view.addConstraints([
            container.topAnchor.constraint(equalTo: view.layoutMarginsGuide.topAnchor),
            container.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
        ])
       
    }
}

