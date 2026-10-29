extension Library {
    /// Every note in a scanned tree, depth first, without the folders: what Quick Open searches.
    public static func notes(in items: [LibraryItem]) -> [LibraryItem] {
        items.flatMap { item in item.isFolder ? notes(in: item.children ?? []) : [item] }
    }
}
