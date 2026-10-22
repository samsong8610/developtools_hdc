var counter = 0;
function add(a, b) {
  var s = a + b;
  counter += s;
  return s;
}
for (var i = 0; i < 3; i++) { add(i, 10); }
print("done counter=" + counter);
