def conv3x3(pixels, kernel):
    assert len(pixels) == 9
    assert len(kernel) == 9

    result = 0

    for p, k in zip(pixels, kernel):
        result += p * k

    return result


pixels = [
    10, 20, 30,
    40, 50, 60,
    70, 80, 90
]

kernel = [
     1,  0, -1,
     1,  0, -1,
     1,  0, -1
]

print(conv3x3(pixels, kernel))
