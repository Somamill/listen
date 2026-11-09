import csv, io, json, os, tempfile,re
from urllib.parse import quote_plus, urlparse
from flask import Blueprint, render_template, request, redirect

discovery = Blueprint("discovery", __name__)
from . import settings
STORE = settings.data_dir()/"goodreads-library.json"
STARTERS = [("Ready Player One", "Ernest Cline", "Science fiction", "An adventure for your next long journey.", "moss"), ("The Martian", "Andy Weir", "Science fiction", "A little ingenuity. A very long way from home.", "rust"), ("World War Z", "Max Brooks", "Fiction", "A world of voices. One extraordinary story.", "slate"), ("The Help", "Kathryn Stockett", "Historical fiction", "Find the voices at the heart of the story.", "gold"), ("Bossypants", "Tina Fey", "Memoir", "Make room for a lighter kind of listen.", "rose"), ("The Book Thief", "Markus Zusak", "Historical fiction", "Settle into a story about the power of words.", "ink")]

STARTER_ISBNS=['9780307887443','9780804139021','9780307346612','9780399155345','9780316056861','9780375831003']

def goodreads_url(title, author):
    return "https://www.goodreads.com/search?q=" + quote_plus(title + " " + author)

def read_library():
    try:
        data = json.loads(STORE.read_text())
        return data if isinstance(data, list) else []
    except (OSError, ValueError):
        return []

def reading_groups(books):
    groups=[{'key':key,'label':label,'books':[]} for key,label in [('to-read','Want to Read'),('currently-reading','Currently Reading'),('read','Read'),('did-not-finish','Did Not Finish'),('other','Other Shelves')]]
    by_key={g['key']:g for g in groups}
    for book in books:
        labels={re.sub(r'[ _]+','-',s.strip().casefold()) for s in book.get('shelf','').split(',')}
        key=next((k for k in ['currently-reading','to-read','read','did-not-finish'] if k in labels),'other')
        by_key[key]['books'].append(book)
    return [g for g in groups if g['books']]

def show_page(error=None):
    from .goodreads_sync import library_tracking
    library=library_tracking(read_library())
    return render_template("discover.html", library_groups=reading_groups(library), starters=[dict(title=t, author=a, genre=g, note=n, color=c, goodreads=goodreads_url(t,a),cover="https://covers.openlibrary.org/b/isbn/"+isbn+"-L.jpg?default=false") for (t,a,g,n,c),isbn in zip(STARTERS,STARTER_ISBNS)], library=library, import_error=error, imported=request.args.get("imported"))

@discovery.get("/discover")
def discover():
    return show_page()

@discovery.post("/goodreads/import")
def import_library():
    upload=request.files.get("library")
    if not upload or not upload.filename:
        return show_page("Choose your Goodreads library CSV export."), 400
    raw=upload.stream.read(2*1024*1024+1)
    if len(raw)>2*1024*1024:
        return show_page("Please choose a CSV smaller than 2 MB."), 400
    try:
        reader=csv.DictReader(io.StringIO(raw.decode("utf-8-sig")))
        if not reader.fieldnames or not {"Title", "Author"}.issubset(reader.fieldnames):
            raise ValueError("Use the Goodreads export with Title and Author columns.")
        books=[];seen=set()
        for row in reader:
            title=(row.get("Title") or "").strip()[:300];author=(row.get("Author") or "").strip()[:200]
            if not title or (title,author) in seen: continue
            seen.add((title,author))
            book_id=(row.get("Book Id") or "").strip()
            link="https://www.goodreads.com/book/show/"+book_id if book_id.isdigit() else goodreads_url(title,author)
            shelf=(row.get("Exclusive Shelf") or "your library").replace("-"," ")[:60]
            rating=row.get("Average Rating", "")
            try:
                numeric=float(rating)
                rating=f"{numeric:.2f}" if 0<numeric<=5 else ""
            except (ValueError, TypeError): rating=""
            isbn=''.join(c for c in (row.get('ISBN13') or row.get('ISBN') or '') if c.isdigit() or c.upper()=='X')
            cover='https://covers.openlibrary.org/b/isbn/'+isbn+'-L.jpg?default=false' if len(isbn) in (10,13) else ''
            books.append(dict(cover=cover,title=title,author=author,goodreads=link,shelf=shelf,rating=rating,color=["moss","rust","slate","gold","rose","ink"][len(books)%6]))
            if len(books)>=500: break
        if not books: raise ValueError("This export does not contain any books.")
        STORE.parent.mkdir(parents=True,exist_ok=True)
        fd,temp=tempfile.mkstemp(dir=STORE.parent,prefix=".goodreads-")
        try:
            with os.fdopen(fd,"w") as f: json.dump(books,f)
            os.replace(temp,STORE)
        finally:
            if os.path.exists(temp): os.unlink(temp)
    except (UnicodeError, csv.Error, ValueError) as exc:
        return show_page(str(exc)), 400
    return redirect("/discover?imported="+str(len(books)))
