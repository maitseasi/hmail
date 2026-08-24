const assert = require("assert")
const { load, deepEqual } = require("./load")

const drive = load("DriveApi.js")

assert.strictEqual(drive.listUrl().indexOf("https://www.googleapis.com/drive/v3/files?"), 0)
assert.ok(drive.listUrl().indexOf("spaces=appDataFolder") > 0)
assert.ok(drive.listUrl().indexOf(encodeURIComponent(drive.FILE_NAME)) > 0)
assert.strictEqual(drive.downloadUrl("../bad"), "")
assert.strictEqual(drive.updateUrl("bad/id"), "")
assert.strictEqual(drive.safeUrl("https://evil.example", "/files", {}), "")

const files = drive.parseFiles({
  files: [
    { id: "z_file", name: drive.FILE_NAME, modifiedTime: "2026-01-02" },
    { id: "a_file", name: drive.FILE_NAME, modifiedTime: "2026-01-01" },
    { id: "ignored", name: "other.json" }
  ]
})
deepEqual(files.map(function(file) { return file.id }), ["a_file", "z_file"])

const multipart = drive.multipartBody('{"version":2}', "boundary_123456789")
assert.ok(multipart.indexOf('"parents":["appDataFolder"]') > 0)
assert.ok(multipart.indexOf('{"version":2}') > 0)
assert.strictEqual(drive.multipartBody("{}", "bad boundary"), "")

assert.strictEqual(drive.responseError(403, {
  error: { message: "Drive API has not been used in project" }
}), "Enable the Google Drive API for this OAuth project")
assert.strictEqual(drive.responseError(412, {}),
  "Cloud workflow data changed on another device")

console.log("test_drive_api.js ok")
