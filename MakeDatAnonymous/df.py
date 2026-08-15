import pandas

def write_txt(data_csv, name, mode, title, sub):
    data = pandas.read_table(data_csv)

    df = pandas.DataFrame(data)

    df_str = df.to_string(index=False, justify='center')

    with open(name, mode) as file:
        if title != "F":
            file.write(title+"\n\n")
        if sub != "F":
            file.write(sub+"\n")
        lines = df_str.split("\n")
        for line in lines:
            file.write(line[1:]+"\n")
