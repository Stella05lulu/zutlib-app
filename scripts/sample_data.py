"""ZutLib sample and real library data loader.

SAMPLE DATA IS FOR DEMONSTRATION ONLY. Every sample row is stored with
is_sample = true, every sample title starts with "Sample", and every sample
PDF opens with the line "SAMPLE PAPER. NOT AN OFFICIAL ZUT EXAMINATION."

Commands (run from the zutlib folder):

    python scripts/sample_data.py seed          add or refresh all sample data
    python scripts/sample_data.py remove        delete every sample row and file
    python scripts/sample_data.py import-real   load seed/real-papers/ and seed/real-books.csv
    python scripts/sample_data.py preview DIR   write the sample PDFs to DIR to look at

seed and remove are idempotent: running them twice gives the same result.
Sample rows have fixed ids, so seeding again updates rather than duplicates.

Real data conventions (nothing here is flagged as sample):

    seed/real-papers/<DEPARTMENT>_<COURSE CODE>_<YEAR>_<exam|test>_<Course title>.pdf
        for example  ICT_ICT 2010_2023_exam_Programming in C.pdf
        DEPARTMENT is ICT, Engineering or Business.
    seed/real-books.csv with the header
        title,author,isbn,department,course_code,edition,total_copies

The service role key is needed because this writes the catalogue directly.
It is read from the terminal only, never from a file:

    PowerShell:  $env:SUPABASE_SERVICE_ROLE_KEY = "..."
                 python scripts/sample_data.py seed
                 Remove-Item Env:SUPABASE_SERVICE_ROLE_KEY

SUPABASE_URL is read from the environment or from .env. Only the Python
standard library is used.
"""

import csv
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
import uuid

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sample_content import BOOKS, COURSES, YEARS  # noqa: E402

BUCKET = "resources"
SAMPLE_PREFIX = "sample"
REAL_PREFIX = "real"
DEPARTMENTS = ("ICT", "Engineering", "Business")
# Fixed namespace so sample ids are the same on every run.
NAMESPACE = uuid.UUID("7d0f3b2e-5a1c-4c9e-9a51-2f3c8e1d0b64")
SAMPLE_LINE = "SAMPLE PAPER. NOT AN OFFICIAL ZUT EXAMINATION."


# ---------------------------------------------------------------- PDF writer
def _pdf_text(s):
    """Escape text for a PDF string and keep it to plain ASCII."""
    s = s.encode("ascii", "replace").decode("ascii")
    return s.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)")


def _wrap(text, width=88):
    words, line, out = text.split(), "", []
    for w in words:
        if len(line) + len(w) + 1 > width:
            out.append(line)
            line = w
        else:
            line = (line + " " + w).strip()
    if line:
        out.append(line)
    return out or [""]


def make_pdf(lines):
    """A small, valid PDF: A4 pages of Helvetica text. Each item in lines
    is (text, size, bold)."""
    pages, current, y = [], [], 800
    for text, size, bold in lines:
        for part in _wrap(text, 88 if size <= 11 else 60):
            step = size + 6
            if y - step < 60:
                pages.append(current)
                current, y = [], 800
            y -= step
            current.append((part, size, bold, y))
    pages.append(current)

    objects = []
    font_regular = 3
    font_bold = 4
    page_ids, content_ids = [], []
    next_id = 5
    for _ in pages:
        page_ids.append(next_id)
        content_ids.append(next_id + 1)
        next_id += 2

    objects.append((1, "<< /Type /Catalog /Pages 2 0 R >>"))
    kids = " ".join(f"{p} 0 R" for p in page_ids)
    objects.append((2, f"<< /Type /Pages /Kids [{kids}] /Count {len(pages)} >>"))
    objects.append((font_regular, "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"))
    objects.append((font_bold, "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold >>"))
    for page, pid, cid in zip(pages, page_ids, content_ids):
        ops = []
        for text, size, bold, ypos in page:
            font = "F2" if bold else "F1"
            ops.append(f"BT /{font} {size} Tf 56 {ypos} Td ({_pdf_text(text)}) Tj ET")
        stream = "\n".join(ops)
        objects.append((pid, f"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] "
                             f"/Resources << /Font << /F1 {font_regular} 0 R /F2 {font_bold} 0 R >> >> "
                             f"/Contents {cid} 0 R >>"))
        objects.append((cid, f"<< /Length {len(stream.encode('latin-1'))} >>\nstream\n{stream}\nendstream"))

    objects.sort()
    out = bytearray(b"%PDF-1.4\n")
    offsets = {}
    for num, body in objects:
        offsets[num] = len(out)
        out += f"{num} 0 obj\n{body}\nendobj\n".encode("latin-1")
    xref = len(out)
    count = len(objects) + 1
    out += f"xref\n0 {count}\n0000000000 65535 f \n".encode("latin-1")
    for num in range(1, count):
        out += f"{offsets[num]:010d} 00000 n \n".encode("latin-1")
    out += f"trailer\n<< /Size {count} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n".encode("latin-1")
    return bytes(out)


# ---------------------------------------------------------------- sample rows
def sample_papers():
    """One test and one examination per course per year, 2019 to 2025."""
    for dept, code, title, questions in COURSES:
        for year in YEARS:
            for kind in ("test_paper", "past_paper"):
                is_exam = kind == "past_paper"
                label = "Sessional examination" if is_exam else "Test 1"
                count = 5 if is_exam else 3
                start = (year * 3 + (0 if is_exam else 5)) % len(questions)
                chosen = [questions[(start + i * 3) % len(questions)] for i in range(count)]
                slug = f"{code.replace(' ', '')}/{year}-{'exam' if is_exam else 'test'}.pdf"
                path = f"{SAMPLE_PREFIX}/{dept}/{slug}"
                lines = [
                    (SAMPLE_LINE, 14, True),
                    ("Practice paper written for ZutLib demonstrations. Questions are original practice questions.", 10, False),
                    ("", 10, False),
                    (f"{code}  {title}", 16, True),
                    (f"{label}, {year} (sample)", 12, False),
                    (f"Answer all {count} questions. Time allowed: {'three hours' if is_exam else 'one hour'}.", 11, False),
                    ("", 10, False),
                ]
                marks = 20 if is_exam else 10
                for i, q in enumerate(chosen, 1):
                    lines.append((f"Question {i}  ({marks} marks)", 12, True))
                    lines.append((q, 11, False))
                    lines.append(("", 10, False))
                lines.append(("End of sample paper.", 10, False))
                row = {
                    "id": str(uuid.uuid5(NAMESPACE, path)),
                    "title": f"Sample {code} {title} {label.lower()} {year}",
                    "type": kind,
                    "department": dept,
                    "course_code": code,
                    "course_title": title,
                    "academic_year": year,
                    "semester": None,
                    "description": "SAMPLE DATA for demonstration only. Not an official ZUT paper.",
                    "file_path": path,
                    "external_url": None,
                    "is_physical": False,
                    "total_copies": 0,
                    "available_copies": 0,
                    "author": None,
                    "isbn": None,
                    "edition": None,
                    "is_sample": True,
                }
                yield row, make_pdf(lines)


def sample_books():
    for title, author, dept, code, edition, total, available in BOOKS:
        yield {
            "id": str(uuid.uuid5(NAMESPACE, f"book:{title}:{author}")),
            "title": f"Sample: {title}",
            "type": "book",
            "department": dept,
            "course_code": code,
            "course_title": None,
            "academic_year": None,
            "semester": None,
            "description": "SAMPLE DATA for demonstration only. Copy counts are invented.",
            "file_path": None,
            "external_url": None,
            "is_physical": True,
            "total_copies": total,
            "available_copies": available,
            "author": author,
            "isbn": None,
            "edition": edition,
            "is_sample": True,
        }


# ---------------------------------------------------------------- Supabase calls
class Api:
    def __init__(self, url, key):
        self.url = url.rstrip("/")
        self.key = key

    def _request(self, method, path, body=None, headers=None, raw=False):
        h = {"apikey": self.key, "Authorization": f"Bearer {self.key}"}
        h.update(headers or {})
        data = body if raw else (json.dumps(body).encode() if body is not None else None)
        if data is not None and not raw:
            h.setdefault("Content-Type", "application/json")
        req = urllib.request.Request(self.url + path, data=data, method=method, headers=h)
        try:
            with urllib.request.urlopen(req, timeout=60) as res:
                text = res.read().decode() if res.length != 0 else ""
                return res.status, (json.loads(text) if text.strip().startswith(("[", "{")) else text)
        except urllib.error.HTTPError as e:
            return e.code, e.read().decode(errors="replace")

    def upsert(self, table, rows):
        for i in range(0, len(rows), 100):
            status, body = self._request(
                "POST", f"/rest/v1/{table}?on_conflict=id", rows[i:i + 100],
                {"Prefer": "resolution=merge-duplicates,return=minimal"})
            if status not in (200, 201, 204):
                raise RuntimeError(f"saving {table} failed ({status}): {body}")

    def select(self, table, query):
        status, body = self._request("GET", f"/rest/v1/{table}?{query}")
        if status != 200:
            raise RuntimeError(f"reading {table} failed ({status}): {body}")
        return body

    def delete(self, table, query):
        status, body = self._request("DELETE", f"/rest/v1/{table}?{query}", headers={"Prefer": "return=minimal"})
        if status not in (200, 204):
            raise RuntimeError(f"deleting from {table} failed ({status}): {body}")

    def upload(self, path, data):
        encoded = "/".join(urllib.parse.quote(p) for p in path.split("/"))
        status, body = self._request(
            "POST", f"/storage/v1/object/{BUCKET}/{encoded}", data,
            {"Content-Type": "application/pdf", "x-upsert": "true"}, raw=True)
        if status not in (200, 201):
            raise RuntimeError(f"uploading {path} failed ({status}): {body}")

    def remove_files(self, paths):
        for i in range(0, len(paths), 100):
            status, body = self._request("DELETE", f"/storage/v1/object/{BUCKET}", {"prefixes": paths[i:i + 100]})
            if status not in (200, 204):
                raise RuntimeError(f"removing files failed ({status}): {body}")


def connect():
    url = os.environ.get("SUPABASE_URL") or _env_file("SUPABASE_URL")
    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY")
    if not url:
        sys.exit("SUPABASE_URL is not set and is not in .env")
    if not key:
        sys.exit("Set SUPABASE_SERVICE_ROLE_KEY in this terminal first (see the top of this file).")
    return Api(url, key)


def _env_file(name):
    if not os.path.exists(".env"):
        return None
    with open(".env", encoding="utf-8") as f:
        for line in f:
            if "=" in line and line.split("=", 1)[0].strip() == name:
                return line.split("=", 1)[1].strip()
    return None


# ---------------------------------------------------------------- commands
def seed(api):
    papers = list(sample_papers())
    for n, (row, pdf) in enumerate(papers, 1):
        api.upload(row["file_path"], pdf)
        if n % 50 == 0:
            print(f"  uploaded {n} of {len(papers)} sample PDFs")
    api.upsert("resources", [row for row, _ in papers])
    books = list(sample_books())
    api.upsert("resources", books)
    print(f"Sample data ready: {len(papers)} sample papers and {len(books)} sample books.")
    print("Every sample row is labelled Sample in the app. Remove it all with: python scripts/sample_data.py remove")


def remove(api):
    rows = api.select("resources", "select=id,file_path&is_sample=is.true")
    ids = [r["id"] for r in rows]
    files = [r["file_path"] for r in rows if r.get("file_path")]
    for i in range(0, len(ids), 100):
        chunk = ",".join(ids[i:i + 100])
        # Borrowing requests for sample books are demo requests too.
        api.delete("borrow_requests", f"resource_id=in.({chunk})")
        api.delete("resources", f"id=in.({chunk})")
    if files:
        api.remove_files(files)
    print(f"Removed {len(ids)} sample rows and {len(files)} sample files.")


def import_real(api, root="seed"):
    papers_dir = os.path.join(root, "real-papers")
    books_csv = os.path.join(root, "real-books.csv")
    accepted, rejected = [], []

    if os.path.isdir(papers_dir):
        for name in sorted(os.listdir(papers_dir)):
            if not name.lower().endswith(".pdf"):
                continue
            row, problem = paper_from_filename(name)
            if problem:
                rejected.append((name, problem))
                continue
            with open(os.path.join(papers_dir, name), "rb") as f:
                data = f.read()
            if not data.startswith(b"%PDF-"):
                rejected.append((name, "not a PDF file"))
                continue
            api.upload(row["file_path"], data)
            api.upsert("resources", [row])
            accepted.append(name)

    if os.path.exists(books_csv):
        with open(books_csv, encoding="utf-8-sig", newline="") as f:
            for line_no, rec in enumerate(csv.DictReader(f), 2):
                row, problem = book_from_csv(rec)
                if problem:
                    rejected.append((f"real-books.csv line {line_no}", problem))
                    continue
                api.upsert("resources", [row])
                accepted.append(f"real-books.csv line {line_no}: {row['title']}")

    print(f"Accepted {len(accepted)}:")
    for a in accepted:
        print(f"  {a}")
    print(f"Rejected {len(rejected)}:")
    for name, why in rejected:
        print(f"  {name}: {why}")


def paper_from_filename(name):
    """'ICT_ICT 2010_2023_exam_Programming in C.pdf' -> a catalogue row."""
    stem = name[:-4]
    parts = stem.split("_", 4)
    if len(parts) != 5:
        return None, "name must be DEPARTMENT_COURSECODE_YEAR_exam|test_Course title.pdf"
    dept, code, year, kind, title = (p.strip() for p in parts)
    if dept not in DEPARTMENTS:
        return None, f"department must be one of {', '.join(DEPARTMENTS)}"
    if not year.isdigit() or not 1990 <= int(year) <= 2100:
        return None, "year must be four digits"
    if kind.lower() not in ("exam", "test"):
        return None, "type must be exam or test"
    if not code or not title:
        return None, "course code and course title are required"
    path = f"{REAL_PREFIX}/{dept}/{code.replace(' ', '')}/{year}-{kind.lower()}-{uuid.uuid5(NAMESPACE, name).hex[:8]}.pdf"
    label = "examination" if kind.lower() == "exam" else "test"
    return {
        "id": str(uuid.uuid5(NAMESPACE, "real:" + name)),
        "title": f"{code} {title} {label} {year}",
        "type": "past_paper" if kind.lower() == "exam" else "test_paper",
        "department": dept, "course_code": code, "course_title": title,
        "academic_year": int(year), "semester": None, "description": None,
        "file_path": path, "external_url": None, "is_physical": False,
        "total_copies": 0, "available_copies": 0,
        "author": None, "isbn": None, "edition": None, "is_sample": False,
    }, None


def book_from_csv(rec):
    title = (rec.get("title") or "").strip()
    author = (rec.get("author") or "").strip()
    dept = (rec.get("department") or "").strip()
    copies = (rec.get("total_copies") or "").strip()
    if not title or not author:
        return None, "title and author are required"
    if dept not in DEPARTMENTS:
        return None, f"department must be one of {', '.join(DEPARTMENTS)}"
    if not copies.isdigit() or not 1 <= int(copies) <= 1000:
        return None, "total_copies must be a whole number from 1 to 1000"
    isbn = "".join(c for c in (rec.get("isbn") or "") if c.isdigit() or c in "Xx").upper() or None
    if isbn and len(isbn) not in (10, 13):
        return None, "ISBN must have 10 or 13 digits"
    return {
        "id": str(uuid.uuid5(NAMESPACE, f"realbook:{title}:{author}")),
        "title": title, "type": "book", "department": dept,
        "course_code": (rec.get("course_code") or "").strip() or None,
        "course_title": None, "academic_year": None, "semester": None, "description": None,
        "file_path": None, "external_url": None, "is_physical": True,
        "total_copies": int(copies), "available_copies": int(copies),
        "author": author, "isbn": isbn, "edition": (rec.get("edition") or "").strip() or None,
        "is_sample": False,
    }, None


def preview(out_dir):
    os.makedirs(out_dir, exist_ok=True)
    n = 0
    for row, pdf in sample_papers():
        name = row["file_path"].replace("/", "_")
        with open(os.path.join(out_dir, name), "wb") as f:
            f.write(pdf)
        n += 1
    print(f"Wrote {n} sample PDFs to {out_dir}")


def main(argv):
    if len(argv) < 2 or argv[1] not in ("seed", "remove", "import-real", "preview"):
        print(__doc__)
        return 1
    if argv[1] == "preview":
        preview(argv[2] if len(argv) > 2 else "sample-preview")
        return 0
    api = connect()
    {"seed": seed, "remove": remove, "import-real": import_real}[argv[1]](api)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
