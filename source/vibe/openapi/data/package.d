/++
	This is here just to workaround these issues with original vibe-d:data package:

		* https://github.com/vibe-d/vibe.d/pull/2274
		* https://github.com/vibe-d/vibe.d/pull/1650
		* https://github.com/vibe-d/vibe.d/pull/2275

	When these'll be fixed/merged, this package would be removed as obsolete and not needed.
+/
module vibe.openapi.data;

public import vibe.openapi.data.json;
