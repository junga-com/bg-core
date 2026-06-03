source /usr/lib/bg_core.sh
import bg_objects.sh

function foo() {
  Try:
    ConstructObject Object obj
    $obj.::dontExist.toString
  Catch: && echo caught
}
foo
