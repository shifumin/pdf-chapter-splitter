# PDF Chapter Splitter

A Ruby command-line tool that automatically detects chapter boundaries in PDF files using their outline/bookmark structure and splits them into individual chapter PDFs. Perfect for breaking down large documents like textbooks, manuals, or reports into manageable chapter-based files.

## Features

- 📖 Automatically detects chapters from PDF outline/bookmarks
- ✂️ Splits PDF into individual chapter files
- 🏗️ Flexible depth-based splitting (split by chapters, sections, or subsections)
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
-d, --depth LEVEL  # Split at specified depth level (default: 1)
-n, --dry-run      # Preview what would be done without actually splitting
-f, --force        # Remove existing chapters/ directory if it exists
-v, --verbose      # Show detailed progress information
-h, --help         # Display help message
```

### Examples

Preview splitting without creating files:
```bash
bundle exec ruby pdf_chapter_splitter.rb -n document.pdf
```

Split at section level (depth 2):
```bash
bundle exec ruby pdf_chapter_splitter.rb -d 2 document.pdf
```

Force overwrite existing output:
```bash
bundle exec ruby pdf_chapter_splitter.rb -f document.pdf
```

Show detailed progress:
```bash
bundle exec ruby pdf_chapter_splitter.rb -v document.pdf
```

Combine options (preview section-level split with verbose output):
```bash
bundle exec ruby pdf_chapter_splitter.rb -d 2 -n -v document.pdf
```

## Output Format

The tool creates files with the following naming convention:

- `00_前付け.pdf` - Front matter (pages before the first chapter)
- `01_Chapter_Title.pdf` - Regular chapters with 2-digit numbering
- `02_Next_Chapter.pdf` - Sequential numbering for each chapter
- `99_付録.pdf` - Appendix (pages after the last chapter)

When splitting at deeper levels (e.g., `-d 2` or higher):
- **All parent levels are included**: Creates PDFs for all hierarchy levels from 1 to the specified depth
- **Filenames include parent context for nested chapters**:
  - `01_Chapter_1.pdf` (complete chapter)
  - `02_Chapter_1_Section_1.1.pdf` (specific section)
  - `03_Chapter_1_Section_1.2.pdf`
  - `04_Chapter_2.pdf` (complete chapter)
  - `05_Chapter_2_Section_2.1.pdf`

Invalid filename characters (`/`, `:`, `*`, `?`, `"`, `<`, `>`, `|`) are automatically replaced with underscores.

## How It Works

1. **Outline Detection**: The tool reads the PDF's built-in outline/bookmark structure
2. **Chapter Identification**: Identifies chapters at the specified depth level (default: top-level)
3. **Intelligent Splitting**:
   - At depth 1: Splits by top-level chapters only
   - At depth 2+: Creates PDFs for **all hierarchy levels** from 1 to the specified depth
   - Includes all chapters without children at or below the target depth
   - If a chapter has no subsections at the target depth, outputs the entire chapter
4. **Page Range Calculation**: Determines the page range for each split section
   - Correctly handles chapters that start on the same page
   - Manages nested chapter relationships for accurate page boundaries
5. **PDF Splitting**: Creates new PDF files for each section, preserving metadata

## Requirements for PDFs

- PDFs must have a proper outline/bookmark structure
- The tool relies on the PDF's internal navigation structure
- PDFs without outlines will show an error message

## Development

### Running Tests

```bash
bundle exec rspec
```

The test suite includes:
- Comprehensive unit tests for all public methods
- Integration tests for the complete workflow
- Edge case testing for error handling
- 100% test coverage for critical functionality

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

### Depth level considerations
- The tool automatically adjusts if the specified depth exceeds the PDF's maximum depth
- Chapters without subsections at the target depth are output as complete chapters
- Use verbose mode (`-v`) to see informational messages about these adjustments

### "chapters directory already exists"
Use the `--force` option to overwrite existing output, or manually remove the directory.

### Encoding Issues
The tool handles UTF-16BE and UTF-8 encoded text. If you encounter issues with special characters, please report them.

### Invalid Command-Line Arguments
The tool validates all command-line arguments and provides clear error messages for invalid inputs (e.g., non-integer depth values).

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

### Dependencies

This project uses the following libraries:
- HexaPDF (AGPL-3.0) - Used for PDF manipulation
- Other dependencies are listed in Gemfile with their respective licenses

