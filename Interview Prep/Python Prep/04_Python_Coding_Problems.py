"""
Python Coding Round – Common Interview Problems (Data Engineer / Snowflake roles)

Every solution includes complexity notes. Run `python 04_Python_Coding_Problems.py`
to execute the self-tests at the bottom.
"""
from collections import Counter, defaultdict, deque, OrderedDict
import heapq
import re


# ---------------------------------------------------------------- Strings
def reverse_string(s):                 # O(n)
    return s[::-1]


def is_palindrome(s):                  # ignore case & non-alphanumerics, O(n)
    clean = re.sub(r"[^a-z0-9]", "", s.lower())
    return clean == clean[::-1]


def is_anagram(a, b):                  # O(n)
    return Counter(a.replace(" ", "").lower()) == Counter(b.replace(" ", "").lower())


def first_non_repeating_char(s):       # O(n)
    counts = Counter(s)
    return next((c for c in s if counts[c] == 1), None)


def char_frequency(s):
    return dict(Counter(s))


def word_count(text):                  # classic "count words in a file"
    return Counter(re.findall(r"\w+", text.lower()))


def compress(s):                       # "aaabbc" -> "a3b2c1"
    if not s:
        return ""
    out, prev, n = [], s[0], 1
    for c in s[1:]:
        if c == prev:
            n += 1
        else:
            out.append(f"{prev}{n}"); prev, n = c, 1
    out.append(f"{prev}{n}")
    return "".join(out)


def longest_unique_substring(s):       # sliding window, O(n)
    seen, start, best = {}, 0, 0
    for i, c in enumerate(s):
        if c in seen and seen[c] >= start:
            start = seen[c] + 1
        seen[c] = i
        best = max(best, i - start + 1)
    return best


def valid_parentheses(s):              # stack, O(n)
    pairs, stack = {")": "(", "]": "[", "}": "{"}, []
    for c in s:
        if c in "([{":
            stack.append(c)
        elif c in pairs:
            if not stack or stack.pop() != pairs[c]:
                return False
    return not stack


# ---------------------------------------------------------------- Lists / arrays
def two_sum(nums, target):             # hash map, O(n)
    seen = {}
    for i, n in enumerate(nums):
        if target - n in seen:
            return [seen[target - n], i]
        seen[n] = i
    return []


def remove_duplicates_keep_order(items):
    return list(dict.fromkeys(items))


def find_duplicates(items):
    return [k for k, v in Counter(items).items() if v > 1]


def second_largest(nums):
    uniq = sorted(set(nums), reverse=True)
    return uniq[1] if len(uniq) > 1 else None


def missing_number(nums):              # 0..n with one missing, O(n)
    n = len(nums)
    return n * (n + 1) // 2 - sum(nums)


def flatten(nested):                   # arbitrary depth
    for x in nested:
        if isinstance(x, (list, tuple)):
            yield from flatten(x)
        else:
            yield x


def chunk(lst, size):                  # batching rows for API / inserts
    return [lst[i:i + size] for i in range(0, len(lst), size)]


def rotate(lst, k):
    k %= len(lst) or 1
    return lst[-k:] + lst[:-k]


def max_subarray(nums):                # Kadane, O(n)
    best = cur = nums[0]
    for n in nums[1:]:
        cur = max(n, cur + n)
        best = max(best, cur)
    return best


def merge_sorted(a, b):                # O(n+m)
    i = j = 0; out = []
    while i < len(a) and j < len(b):
        if a[i] <= b[j]:
            out.append(a[i]); i += 1
        else:
            out.append(b[j]); j += 1
    return out + a[i:] + b[j:]


def top_k_frequent(nums, k):           # heap, O(n log k)
    return [x for x, _ in Counter(nums).most_common(k)]


def kth_largest(nums, k):
    return heapq.nlargest(k, nums)[-1]


def merge_intervals(intervals):        # e.g. overlapping sessions, O(n log n)
    out = []
    for s, e in sorted(intervals):
        if out and s <= out[-1][1]:
            out[-1][1] = max(out[-1][1], e)
        else:
            out.append([s, e])
    return out


def binary_search(arr, target):        # O(log n)
    lo, hi = 0, len(arr) - 1
    while lo <= hi:
        mid = (lo + hi) // 2
        if arr[mid] == target:
            return mid
        lo, hi = (mid + 1, hi) if arr[mid] < target else (lo, mid - 1)
    return -1


# ---------------------------------------------------------------- Math classics
def fibonacci(n):
    a, b = 0, 1
    for _ in range(n):
        yield a
        a, b = b, a + b


def is_prime(n):
    if n < 2:
        return False
    return all(n % i for i in range(2, int(n ** 0.5) + 1))


def factorial(n):
    return 1 if n <= 1 else n * factorial(n - 1)


def fizzbuzz(n):
    return ["FizzBuzz" if i % 15 == 0 else "Fizz" if i % 3 == 0 else
            "Buzz" if i % 5 == 0 else str(i) for i in range(1, n + 1)]


# ---------------------------------------------------------------- Dicts / data-engineering style
def group_by_key(records, key):        # like SQL GROUP BY
    out = defaultdict(list)
    for r in records:
        out[r[key]].append(r)
    return dict(out)


def sum_by(records, key, val):
    out = defaultdict(float)
    for r in records:
        out[r[key]] += r[val]
    return dict(out)


def latest_per_key(records, key, ts):  # dedupe like ROW_NUMBER() = 1
    best = {}
    for r in records:
        if r[key] not in best or r[ts] > best[r[key]][ts]:
            best[r[key]] = r
    return list(best.values())


def flatten_dict(d, parent="", sep="_"):   # flatten nested JSON
    items = {}
    for k, v in d.items():
        nk = f"{parent}{sep}{k}" if parent else k
        if isinstance(v, dict):
            items.update(flatten_dict(v, nk, sep))
        else:
            items[nk] = v
    return items


def merge_dicts(a, b):
    return {**a, **b}


def invert_dict(d):
    return {v: k for k, v in d.items()}


def left_join(left, right, key):       # join two lists of dicts
    idx = {r[key]: r for r in right}
    return [{**l, **idx.get(l[key], {})} for l in left]


def schema_diff(src_cols, tgt_cols):   # schema drift detection
    s, t = set(src_cols), set(tgt_cols)
    return {"added": sorted(s - t), "removed": sorted(t - s)}


def parse_log_errors(lines):           # count ERROR by service from log lines
    pat = re.compile(r"^(\S+ \S+) (ERROR|WARN|INFO) \[(\w+)\]")
    c = Counter()
    for line in lines:
        m = pat.match(line)
        if m and m.group(2) == "ERROR":
            c[m.group(3)] += 1
    return dict(c)


# ---------------------------------------------------------------- Design-ish
class LRUCache:                        # O(1) get/put
    def __init__(self, capacity):
        self.cap, self.data = capacity, OrderedDict()

    def get(self, k):
        if k not in self.data:
            return -1
        self.data.move_to_end(k)
        return self.data[k]

    def put(self, k, v):
        self.data[k] = v
        self.data.move_to_end(k)
        if len(self.data) > self.cap:
            self.data.popitem(last=False)


def topological_sort(deps):            # task DAG ordering (Airflow / Snowflake Task graph)
    """deps: {task: [upstream tasks]} -> valid execution order, raises on cycle."""
    indeg = {t: 0 for t in deps}
    children = defaultdict(list)
    for t, ups in deps.items():
        for u in ups:
            indeg.setdefault(u, 0)
            children[u].append(t)
            indeg[t] += 1
    q = deque(sorted(t for t, d in indeg.items() if d == 0))
    order = []
    while q:
        t = q.popleft(); order.append(t)
        for c in children[t]:
            indeg[c] -= 1
            if indeg[c] == 0:
                q.append(c)
    if len(order) != len(indeg):
        raise ValueError("cycle detected")
    return order


# ---------------------------------------------------------------- Self-tests
if __name__ == "__main__":
    assert reverse_string("abc") == "cba"
    assert is_palindrome("A man, a plan, a canal: Panama")
    assert is_anagram("Listen", "Silent")
    assert first_non_repeating_char("swiss") == "w"
    assert word_count("a b a")["a"] == 2
    assert compress("aaabbc") == "a3b2c1"
    assert longest_unique_substring("abcabcbb") == 3
    assert valid_parentheses("{[()]}") and not valid_parentheses("(]")
    assert two_sum([2, 7, 11, 15], 9) == [0, 1]
    assert remove_duplicates_keep_order([3, 1, 3, 2, 1]) == [3, 1, 2]
    assert sorted(find_duplicates([1, 2, 2, 3, 3])) == [2, 3]
    assert second_largest([5, 5, 3, 9]) == 5
    assert missing_number([0, 1, 3]) == 2
    assert list(flatten([1, [2, [3, (4,)]]])) == [1, 2, 3, 4]
    assert chunk([1, 2, 3, 4, 5], 2) == [[1, 2], [3, 4], [5]]
    assert rotate([1, 2, 3, 4], 1) == [4, 1, 2, 3]
    assert max_subarray([-2, 1, -3, 4, -1, 2, 1, -5, 4]) == 6
    assert merge_sorted([1, 3], [2, 4]) == [1, 2, 3, 4]
    assert top_k_frequent([1, 1, 1, 2, 2, 3], 2) == [1, 2]
    assert kth_largest([3, 2, 1, 5, 6, 4], 2) == 5
    assert merge_intervals([[1, 3], [2, 6], [8, 10]]) == [[1, 6], [8, 10]]
    assert binary_search([1, 3, 5, 7], 5) == 2
    assert list(fibonacci(6)) == [0, 1, 1, 2, 3, 5]
    assert is_prime(29) and not is_prime(1)
    assert factorial(5) == 120
    assert fizzbuzz(15)[-1] == "FizzBuzz"

    recs = [{"id": 1, "r": "US", "amt": 10, "ts": 1},
            {"id": 1, "r": "US", "amt": 20, "ts": 2},
            {"id": 2, "r": "EU", "amt": 5, "ts": 1}]
    assert len(group_by_key(recs, "r")["US"]) == 2
    assert sum_by(recs, "r", "amt") == {"US": 30, "EU": 5}
    assert {r["amt"] for r in latest_per_key(recs, "id", "ts")} == {20, 5}
    assert flatten_dict({"a": {"b": {"c": 1}}, "d": 2}) == {"a_b_c": 1, "d": 2}
    assert left_join([{"k": 1}], [{"k": 1, "v": "x"}], "k") == [{"k": 1, "v": "x"}]
    assert schema_diff(["a", "b", "c"], ["a", "d"]) == {"added": ["b", "c"], "removed": ["d"]}
    logs = ["2026-11-23 10:00:01 ERROR [loader] timeout",
            "2026-11-23 10:00:02 INFO [loader] ok",
            "2026-11-23 10:00:03 ERROR [api] 500"]
    assert parse_log_errors(logs) == {"loader": 1, "api": 1}

    c = LRUCache(2); c.put(1, 1); c.put(2, 2); c.get(1); c.put(3, 3)
    assert c.get(2) == -1 and c.get(1) == 1
    assert topological_sort({"load": ["extract"], "transform": ["load"], "extract": []}) \
        == ["extract", "load", "transform"]
    print("All tests passed")
