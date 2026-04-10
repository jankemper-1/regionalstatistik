

#################################################################################
######## Big file
#################################################################################

library(httr)

BASE_URL <- "https://www.regionalstatistik.de/genesisws/rest/2020"
USERNAME <- Sys.getenv("GENESIS_USERNAME")
PASSWORD <- Sys.getenv("GENESIS_PASSWORD")
TABELLE  <- "13211-01-03-5"

# --- Test login ---
r2 <- POST(
  url  = paste0(BASE_URL, "/helloworld/logincheck"),
  body = list(
    username = USERNAME,
    password = pw_encoded,
    language = "de"
  ),
  encode = "form"
)
cat("Status:", status_code(r2), "\n")

## find table numbers
# --- Step 0: Check tables start with 13211 ---
# You find the correct numbers in online database
# r_find <- POST(
#   url = paste0(BASE_URL, "/find/find"),
#   add_headers(username = USERNAME, password = PASSWORD),
#   body = list(term = "13211", category = "tables",
#               pagelength = "50", language = "de"),
#   encode = "form"
# )
# 

# --- Step 1: Start job ---
r_job <- POST(
  url = paste0(BASE_URL, "/data/tablefile"),
  add_headers(username = USERNAME, password = PASSWORD),
  body = list(
    name      = TABELLE,
    area      = "free",
    format    = "ffcsv", # flat file
    compress  = "false",
    transpose = "false",
    job       = "true",
    language  = "de"
  ),
  encode = "form"
)

job_response <- content(r_job, "parsed", encoding = "UTF-8")
cat("Job gestartet:", job_response$Status$Content, "\n")
job_id <- job_response$Parameter$name
cat("Job-ID:", job_id, "\n")

# --- Step 2: wait until job is done ---
repeat {
  Sys.sleep(15)
  
  r_jobs <- POST(
    url = paste0(BASE_URL, "/catalogue/jobs"),
    add_headers(username = USERNAME, password = PASSWORD),
    body = list(
      type       = "tablefile",
      pagelength = "50",
      language   = "de"
    ),
    encode = "form"
  )
  
  jobs <- content(r_jobs, "parsed")$List
  job  <- Filter(function(j) grepl(TABELLE, j$Code, fixed = TRUE), jobs)
  
  if (length(job) > 0) {
    status <- job[[1]]$State
    cat(Sys.time(), "- Job-Status:", status, "\n")
    if (tolower(status) %in% c("fertig", "finished")) {
      job_id <- job[[1]]$Code
      break
    }
  } else {
    cat(Sys.time(), "- Job noch nicht in Liste...\n")
  }
}

# --- Step 3: download results ---
r_result <- POST(
  url = paste0(BASE_URL, "/data/resultfile"),
  add_headers(username = USERNAME, password = PASSWORD),
  body = list(
    name     = job_id,
    format   = "ffcsv",
    compress = "false",
    language = "de"
  ),
  encode = "form"
)

if (http_error(r_result)) {
  stop("Download-Fehler: ", content(r_result, "text", encoding = "UTF-8"))
}

# --- Step 4: unpack zip files ---
zip_path <- tempfile(fileext = ".zip")
writeBin(content(r_result, "raw"), zip_path)
on.exit(unlink(zip_path))

csv_name    <- unzip(zip_path, list = TRUE)$Name[1]
extract_dir <- tempdir()
unzip(zip_path, files = csv_name, exdir = extract_dir)
csv_path <- file.path(extract_dir, csv_name)

df <- read.csv(csv_path, sep = ";", encoding = "UTF-8",
               na.strings = c("", "-", ".", "/", "...", "x"),
               check.names = FALSE, stringsAsFactors = FALSE)

message(nrow(df), " Zeilen, ", ncol(df), " Spalten")
print(head(df))

