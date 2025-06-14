# PDF Chapter Splitter

A Ruby command-line tool that automatically detects chapter boundaries in PDF files using their outline/bookmark structure and splits them into individual chapter PDFs. Perfect for breaking down large documents like textbooks, manuals, or reports into manageable chapter-based files.

## Features

- 📖 Automatically detects chapters from PDF outline/bookmarks
- ✂️ Splits PDF into individual chapter files
- 🇯🇵 Supports Japanese and international character sets
- 📋 Handles front matter and appendices
- 🔍 Dry-run mode to preview splitting before execution
- 💪 Force mode to overwrite existing output
- 📊 Verbose mode for detailed progress tracking

## Requirements

- Ruby 3.4.4 or higher
- Bundler

## Installation

1. Clone the repository:
```bash
git clone https://github.com/yourusername/pdf-chapter-splitter.git
cd pdf-chapter-splitter
```

2. Install dependencies:
```bash
bundle install
```

## Usage

### Basic Usage

```bash
bundle exec ruby pdf_chapter_splitter.rb document.pdf
```

This will:
1. Read the PDF's outline structure
2. Create a `chapters/` directory in the same location as the PDF
3. Split the PDF into individual chapter files

### Command Line Options

```bash
-n, --dry-run    # Preview what would be done without actually splitting
-f, --force      # Remove existing chapters/ directory if it exists
-v, --verbose    # Show detailed progress information
-h, --help       # Display help message
```

### Examples

Preview splitting without creating files:
```bash
bundle exec ruby pdf_chapter_splitter.rb -n document.pdf
```

Force overwrite existing output:
```bash
bundle exec ruby pdf_chapter_splitter.rb -f document.pdf
```

Show detailed progress:
```bash
bundle exec ruby pdf_chapter_splitter.rb -v document.pdf
```

Combine options:
```bash
bundle exec ruby pdf_chapter_splitter.rb -n -v document.pdf
```

## Output Format

The tool creates files with the following naming convention:

- `00_前付け.pdf` - Front matter (pages before the first chapter)
- `01_Chapter_Title.pdf` - Regular chapters with 2-digit numbering
- `02_Next_Chapter.pdf` - Sequential numbering for each chapter
- `99_付録.pdf` - Appendix (pages after the last chapter)

Invalid filename characters (`/`, `:`, `*`, `?`, `"`, `<`, `>`, `|`) are automatically replaced with underscores.

## How It Works

1. **Outline Detection**: The tool reads the PDF's built-in outline/bookmark structure
2. **Chapter Identification**: Only top-level outline items are treated as chapters
3. **Page Range Calculation**: Determines the page range for each chapter
4. **PDF Splitting**: Creates new PDF files for each chapter, preserving metadata

## Requirements for PDFs

- PDFs must have a proper outline/bookmark structure
- The tool relies on the PDF's internal navigation structure
- PDFs without outlines will show an error message

## Development

### Running Tests

```bash
bundle exec rspec
```

### Running Linter

```bash
bundle exec rubocop
bundle exec rubocop -a  # Auto-fix issues
```

### Generating Test PDFs

```bash
bundle exec ruby spec/support/generate_test_pdfs.rb
```

## Troubleshooting

### "No outline found in the PDF file"
The PDF doesn't have bookmarks/outline. This tool requires PDFs with proper chapter structure.

### "chapters directory already exists"
Use the `--force` option to overwrite existing output, or manually remove the directory.

### Encoding Issues
The tool handles UTF-16BE and UTF-8 encoded text. If you encounter issues with special characters, please report them.

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## Acknowledgments

- Uses [pdf-reader](https://github.com/yob/pdf-reader) for PDF outline parsing
- Uses [HexaPDF](https://hexapdf.gettalong.org/) for PDF manipulation
