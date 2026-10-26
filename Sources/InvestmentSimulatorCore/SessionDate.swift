/// True for a market session's date written `yyyy-MM-dd`, which sorts as text.
func isSessionDate(_ text: String) -> Bool {
    text.wholeMatch(of: /\d{4}-\d{2}-\d{2}/) != nil
}
