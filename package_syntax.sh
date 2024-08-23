#!/bin/bash -x
#
# DIY rebuild of all binary framework zip files from source.
# This script takes about half an hour to run through.
#
# Make a fork of https://github.com/johnno1962/InstantSyntax
# clone it and run this file inside the clone. After completion,
# edit binary targets in Package.swift for the updated checksums
# using copy and paste and the base URL of your fork then commit.
# The zver in Package.swift needs to tie with a tag on your fork.
#
# The command to create the swift_syntax.xcodeproj (Xcode 13) is:
# swift package generate-xcodeproj
#

DD=./build
TAG=509.1.1
DEST=../swift-syntax-binary/$TAG
SOURCE=../swift-syntax
CONFIG=release

cd "$(dirname "$0")" &&
if [ ! -d $SOURCE ]; then
  git clone https://github.com/apple/swift-syntax.git $SOURCE
  cp -rf swift-syntax.xcodeproj $SOURCE
fi

cd $SOURCE &&
git stash &&
git checkout $TAG &&

# This seems to be the easiest way to regenerate the plugin static library.
sed -e 's/, targets: /, type: .static, targets: /' Package.swift >P.swift &&
mv -f P.swift Package.swift &&
# arch -arm64 swift build -c $CONFIG &&
arch -x86_64 swift build -c $CONFIG &&
mkdir -p $DEST &&
lipo -create .build/*-apple-macosx/$CONFIG/libSwiftCompilerPlugin.a -output $DEST/libSwiftSyntax.a &&
git checkout Package.swift &&

# These patches required when using xcodebuild.
git apply -v <<PATCH &&
diff --git a/Sources/SwiftSyntaxMacrosTestSupport/Assertions.swift b/Sources/SwiftSyntaxMacrosTestSupport/Assertions.swift
index 6ff8ba2b..5c776b2f 100644
--- a/Sources/SwiftSyntaxMacrosTestSupport/Assertions.swift
+++ b/Sources/SwiftSyntaxMacrosTestSupport/Assertions.swift
@@ -358,3 +358,9 @@ public func assertMacroExpansion(
     }
   }
 }
+
+func XCTFail(_ msg: String, file: StaticString = #file, line: UInt = #line) {
+
+}
+func XCTAssertEqual<G: Equatable>(_ a: G, _ b: G, _ msg: String = "?", file: StaticString = #file, line: UInt = #line) {
+}
diff --git a/Sources/_SwiftSyntaxTestSupport/AssertEqualWithDiff.swift b/Sources/_SwiftSyntaxTestSupport/AssertEqualWithDiff.swift
index 5cbdba15..1f51b91a 100644
--- a/Sources/_SwiftSyntaxTestSupport/AssertEqualWithDiff.swift
+++ b/Sources/_SwiftSyntaxTestSupport/AssertEqualWithDiff.swift
@@ -143,3 +143,21 @@ public func failStringsEqualWithDiff(
     XCTFail(fullMessage, file: file, line: line)
   }
 }
+
+func XCTFail(_ msg: String, file: StaticString = #file, line: UInt = #line) {
+
+}
+func XCTAssertTrue(_ msg: Bool, file: StaticString = #file, line: UInt = #line) {
+
+}
+func XCTAssert(_ opt: Bool, _ msg: String = "?", file: StaticString = #file, line: UInt = #line) {
+
+}
+func XCTAssertNil<G>(_ opt: Optional<G>, file: StaticString = #file, line: UInt = #line) {
+
+}
+func XCTUnwrap<G>(_ opt: Optional<G>, file: StaticString = #file, line: UInt = #line) -> G {
+  return opt!
+}
+func XCTAssertEqual<G>(_ a: G, _ b: G, _ msg: String = "?", file: StaticString = #file, line: UInt = #line) {
+}
PATCH

if [ ! -d build ]; then
  for sdk in macosx iphonesimulator iphoneos; do
    xcodebuild archive -target SwiftSyntax-all -sdk $sdk -project swift-syntax.xcodeproj BUILD_LIBRARY_FOR_DISTRIBUTION=YES SWIFT_SERIALIZE_DEBUGGING_OPTIONS=NO || exit 1
  done
fi &&

for module in SwiftBasicFormat SwiftCompilerPlugin SwiftCompilerPluginMessageHandling SwiftDiagnostics SwiftOperators SwiftParser SwiftParserDiagnostics SwiftSyntax SwiftSyntax509 SwiftSyntaxBuilder SwiftSyntaxMacroExpansion SwiftSyntaxMacros SwiftSyntaxMacrosTestSupport _SwiftSyntaxTestSupport; do

    PLATFORMS=""
    for p in $DD/UninstalledProducts/*/$module.framework; do
#      codesign -f --timestamp -s "Apple Development: lyzkov@gmail.com (LUXWCD73JG)" $p || exit 1
      PLATFORMS="$PLATFORMS -framework $p"
    done

    rm -rf $DEST/$module.xcframework
    xcodebuild -create-xcframework $PLATFORMS -output $DEST/$module.xcframework || exit 1
done &&

cd $DEST &&
rm -f *.zip &&
zip -9 libSwiftSyntax.a.zip libSwiftSyntax.a &&

for f in *.xcframework; do
#    codesign --timestamp -v --sign "Apple Development: lyzkov@gmail.com (LUXWCD73JG)" $f
    zip -r9 --symlinks "$f.zip"  "$f" >>../../zips.txt
    CHECKSUM=`swift package compute-checksum $f.zip`
    cat <<"HERE" | sed -e s/__NAME__/$f/g | sed -e s/.xcframework\",/\",/g | sed -e s/__CHECKSUM__/$CHECKSUM/g | tee -a ../Package.swift
    .binaryTarget(
        name: "__NAME__",
        url: repo + "__NAME__.zip",
        checksum: "__CHECKSUM__"
    ),
HERE
done

echo "Build complete, edit Package.swift to update the checksums"
