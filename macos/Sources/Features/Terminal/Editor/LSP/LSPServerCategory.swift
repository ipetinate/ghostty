import Foundation

/// The kind of language an extension deals in, used to group the store's
/// listing into readable sections.
///
/// Declared by the registry index, one or more per entry — the settings list
/// this used to group is gone, and nothing in this build guesses a family for
/// an entry that declares none.
///
/// Deliberately coarser than "one category per extension": the point of the
/// grouping is that a reader scanning for "the Python one" or "the one for C"
/// can land in the right neighborhood without reading every row.
enum LSPServerCategory: String, CaseIterable, Hashable, Sendable, Identifiable {
    /// Interpreted or just-in-time languages whose sources run as-is.
    case script

    /// Languages that are compiled to native code or bytecode before
    /// running.
    case compiled

    /// HTML, Markdown and friends — structured text for documents.
    case markup

    /// The frameworks that put a language inside a file of their own —
    /// `.vue`, `.svelte`, `.astro`. Their servers are not script servers
    /// even though the file holds script: one file carries a template, a
    /// style block and a script block, and it takes two processes to serve.
    /// Filing them under Script hid the fact that they behave differently
    /// from every row there.
    case frontendFramework

    /// CSS and its preprocessors.
    case styles

    /// JSON, YAML and other structured data.
    case data

    /// Infrastructure-as-code.
    case infrastructure

    var id: String { rawValue }

    /// The heading shown over a group of the store's listing.
    ///
    /// The groups are ordered by this string, not by the order the cases are
    /// declared in — so a reader hunting for one scans alphabetically instead
    /// of learning which family somebody decided was important.
    var title: String {
        switch self {
        case .script: return "Script"
        case .frontendFramework: return "Frontend Frameworks"
        case .compiled: return "Compiled"
        case .markup: return "Markup"
        case .styles: return "Styles"
        case .data: return "Data"
        case .infrastructure: return "Infrastructure"
        }
    }

    /// An SF Symbol for the heading, when the row icon isn't enough to
    /// distinguish one group from the next.
    var systemImage: String {
        switch self {
        case .script: return "chevron.left.forwardslash.chevron.right"
        case .frontendFramework: return "square.stack.3d.up"
        case .compiled: return "hammer"
        case .markup: return "doc.richtext"
        case .styles: return "paintbrush"
        case .data: return "tablecells"
        case .infrastructure: return "server.rack"
        }
    }
}
