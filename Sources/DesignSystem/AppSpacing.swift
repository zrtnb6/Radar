import CoreFoundation

enum AppSpacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 20
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

enum AppLayout {
    static let sidebarMinimum: CGFloat = 260
    static let sidebarIdeal: CGFloat = 300
    static let sidebarMaximum: CGFloat = 340
    static let contentPadding: CGFloat = AppSpacing.xl
    static let sectionSpacing: CGFloat = AppSpacing.lg
    static let cardPadding: CGFloat = AppSpacing.lg
    static let controlHeight: CGFloat = 28
    static let rowIconSize: CGFloat = 40
    static let detailIconSize: CGFloat = 52
    static let rowHeight: CGFloat = 86
}
