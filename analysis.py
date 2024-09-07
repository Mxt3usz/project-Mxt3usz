import pandas as pd
import matplotlib.pyplot as plt
import matplotlib.patches as patch
from matplotlib.dates import YearLocator
import geopandas as gpd
from shapely.geometry import Point

# read the csv file
df = pd.read_csv("Motor_Vehicle_Collisions_-_Crashes.csv", low_memory=False)
df = df.drop_duplicates()  # if any duplicates drop them


# sets the visibility of the x-axis ticks
def tick_visibility(axis, step=2):
    for i, tick in enumerate(axis.get_xticklabels()):
        if i % step != 0:
            tick.set_visible(False)


def top_10_contributing_factors(df):
    # clean up spelling/ambiguity mistakes we dont want to
    # have one time Illness and other time Illnes
    # I took the word which appeared more often in table as the correct one
    variations = {
        "Illness": "Illnes",
        "Drugs (illegal)": "Drugs (Illegal)",
        "Cell Phone (hand-Held)": "Cell Phone (hand-held)",
        "Reaction to Uninvolved Vehicle": "Reaction to Other Uninvolved Vehicle",
    }
    fac = "CONTRIBUTING FACTOR VEHICLE"
    # df for each contributing factor, we want to look in each possible
    # column for contributing factors and count the number of times they appear
    dfs = [pd.DataFrame() for column in df.columns if column.startswith(fac)]
    all_factors = pd.DataFrame()
    for i in range(len(dfs)):
        # select only the contributing factor and id columns from df
        dfs[i] = df.filter(items=[f"{fac} {i+1}", "COLLISION_ID"])
        # generalize factors to one (rename) so we can unionize them
        dfs[i] = dfs[i].rename(columns={f"{fac} {i+1}": fac})
        # remove all variations of same word for each dataframe
        for correct, wrong in variations.items():
            dfs[i] = dfs[i].replace(wrong, correct)
        # remove unspecified factor rows
        dfs[i] = dfs[i][dfs[i][fac] != "Unspecified"]
    # unionize all dfs
    all_factors = pd.concat(dfs)
    # group by the contributing factor and use aggregation count()
    # to count the number of times a factor appears
    all_factors = all_factors.groupby(fac).count()
    # sort the factors after crash counts in asc order
    all_factors = all_factors = all_factors.sort_values(
        by="COLLISION_ID", ascending=True
    )
    all_factors = all_factors.tail(10)  # get Top 10
    c = 0
    wrap = []
    curr_str = ""
    # wrap the factors so they fit in the plot
    # after every second " " or / add a newline
    for factor in all_factors.index:
        curr_str = ""
        c = 0
        for i in range(len(factor)):
            if factor[i] == " " or factor[i] == "/":
                c += 1
                if c != 0 and c % 2 == 0:
                    curr_str += "\n"
            curr_str += factor[i]
        wrap += [curr_str]
    # plot hbar chart with top 10 contributing factors
    fig, axis = plt.subplots(1, 1, figsize=(8, 6))
    all_factors = all_factors.reset_index()
    all_factors["CONTRIBUTING FACTORS"] = wrap
    all_factors.plot(
        kind="barh",
        legend=False,
        ax=axis,
        x="CONTRIBUTING FACTORS",
        y="COLLISION_ID",
        fontsize=12,
    )
    plt.subplots_adjust(
        left=0.208, right=0.999, top=0.88, bottom=0.11, wspace=0.2, hspace=0.2
    )
    axis.set_title("Top 10 Crash Contributory Factors in NYC [2012-2024]", fontsize=16)
    axis.set_axisbelow(True)  # Setting the grid lines behind the bars
    plt.grid(True)
    # Setting x-axis ticks at intervals of 50k
    plt.xticks(range(0, 550001, 50000))
    # only show every second tick for clarity
    tick_visibility(axis)
    plt.ylabel("")
    plt.xlabel("Frequency of Factor Contributing to Crash", fontsize=12)
    plt.savefig("top_10_contributing_factors.pdf")
    plt.show()


def boroughs_by_crashes(df):
    crashes = df.filter(items=["LATITUDE", "LONGITUDE", "COLLISION_ID"])
    # drop all rows with NaN values
    crashes = crashes.dropna()
    # function to merge lat and long into one column -> Point(long, lat)
    f = lambda row: Point(row["LONGITUDE"], row["LATITUDE"])
    # apply f to each row in crashes and put result in geometry column
    # geometry column is used to spatial jpoin with nyc boroughs
    crashes["geometry"] = crashes.apply(f, axis=1)  # axis=1 for row-wise
    crashes = crashes.filter(items=["geometry", "COLLISION_ID"])
    # convert dataframe to geodataframe to be able to use spatial join
    # crashes uses espg 4326 (specified on the web page)
    crashes = gpd.GeoDataFrame(crashes, crs="EPSG:4326")
    # load nyc boroughs table, which uses espg 2263
    nyc = gpd.read_file(gpd.datasets.get_path("nybb"))
    # to be able to do spatial join crs has to be same convert
    # wrong crs of crashes to ny.crs = 2263
    crashes = crashes.to_crs(nyc.crs)
    # with spatial join we can look if our Point(long, lat) intersects
    # with any of the Points in the geometry column of nyc if yes then
    # we know in which borough the crash happened use natural join to prune
    crashes_sj_nyc = crashes.sjoin(nyc, how="inner")
    crashes_sj_nyc = crashes_sj_nyc.filter(items=["BoroName", "COLLISION_ID"])
    # get borough columns to see if we missed some crashes
    # since lat long can be nil where borough is not
    borough_id = df.filter(items=["BOROUGH", "COLLISION_ID"])
    borough_id = borough_id.dropna()
    # get all rows from borough_id which are not in crashes_sj_nyc
    missing = borough_id[
        ~borough_id["COLLISION_ID"].isin(crashes_sj_nyc["COLLISION_ID"])
    ]
    missing = missing.rename(columns={"BOROUGH": "BoroName"})
    # add the missing crashes to crashes_sj_nyc
    crashes_sj_nyc = pd.concat([crashes_sj_nyc, missing])
    # group by lowercase BoroName case and count crashes
    crashes_sj_nyc = crashes_sj_nyc.groupby(
        crashes_sj_nyc["BoroName"].str.lower()
    ).count()
    # new BoroName was created we have to drop it and reset index
    crashes_sj_nyc = crashes_sj_nyc.drop("BoroName", axis=1).reset_index()
    # merge the crashes_sj_nyc with nyc to get the geometry column for plot
    nyc = nyc.merge(
        crashes_sj_nyc,
        left_on=nyc["BoroName"].str.lower(),
        right_on=crashes_sj_nyc["BoroName"].str.lower(),
    )
    # sort borough names in descending order for legend
    nyc = nyc.sort_values(by="COLLISION_ID", ascending=False)
    # plot the choropleth map
    fig, axis = plt.subplots(1, 1, figsize=(6, 6))
    # set epsg:4326 as the geographic coordinate system
    nyc = nyc.to_crs(epsg=4326)
    nyc.plot(
        column="COLLISION_ID",
        cmap="Blues",
        legend=True,
        ax=axis,
        legend_kwds={"label": "Total Crash Incidents over 10 years"},
        edgecolor="black",
    )
    plt.subplots_adjust(
        left=0.102, right=0.952, top=0.88, bottom=0.11, wspace=0.2, hspace=0.2
    )
    axis.set_title("Crash Distribution over Boroughs in NYC [2012-2024]")
    # Extract the colors used in the plot
    cmap = plt.cm.get_cmap("Blues")
    # normalize crashes column to fit the range of the cmap [0 .. 1]
    norm = plt.Normalize(nyc["COLLISION_ID"].min(), nyc["COLLISION_ID"].max())
    # based on norm mapping (crashes -> color) get color of borough
    colors = [cmap(norm(crashes)) for crashes in nyc["COLLISION_ID"]]
    boroughs = [borough for borough in nyc["BoroName_x"]]
    # create a legend with the colors and boroughs
    patches = [
        patch.Patch(color=colors[i], label=boroughs[i]) for i in range(len(boroughs))
    ]
    plt.legend(handles=patches, loc="upper left")
    axis.set_axisbelow(True)
    plt.grid(True)
    plt.ylabel("Latitude (°)")
    plt.xlabel("Longitude (°)")
    plt.savefig("boroughs_by_crashes.pdf")
    plt.show()


def crashes_over_time(df):
    crashes_time = df.filter(items=["CRASH DATE", "COLLISION_ID"])
    # parse all rows of CRASH DATE column to datetime object
    crashes_time["CRASH DATE"] = pd.to_datetime(crashes_time["CRASH DATE"])
    # set CRASH DATE as index to use functions on datetime objects
    crashes_time = crashes_time.set_index("CRASH DATE")
    # resample to group dates by month and count number of crashes for each mo
    crashes_time = crashes_time.resample("ME").count()
    fig, axis = plt.subplots(1, 1, figsize=(6, 4))
    # first plot the line plot then overlay it with scatter plot
    axis.plot(crashes_time.index, crashes_time["COLLISION_ID"])
    axis.scatter(crashes_time.index, crashes_time["COLLISION_ID"], s=5)
    plt.subplots_adjust(
        left=0.138, right=0.977, top=0.88, bottom=0.11, wspace=0.2, hspace=0.2
    )
    axis.set_title("Monthly Crash Incidents in NYC [2012-2024]")
    axis.set_xlabel("Year")
    axis.set_ylabel("Total Crash Incidents per Month")
    # remove last month since it is not complete
    axis.set_xlim(crashes_time.index[0], crashes_time.index[-2])
    # add one more tick to the x-axis to make it look better
    axis.set_xticks(axis.get_xticks().tolist() + [axis.get_xticks()[0] + 1])
    # make x-axis ticks appear at each year
    axis.xaxis.set_major_locator(YearLocator())
    tick_visibility(axis)
    axis.set_axisbelow(True)
    plt.grid(True)
    plt.savefig("crashes_over_time.pdf")
    plt.show()


def crashes_by_time(df):
    crashes_time = df.filter(items=["CRASH TIME", "COLLISION_ID"])
    crashes_time["CRASH TIME"] = pd.to_datetime(
        crashes_time["CRASH TIME"], format="%H:%M"
    )
    crashes_time = crashes_time.set_index("CRASH TIME")
    # resample to group times by hour and count number of crashes for each hour
    crashes_time = crashes_time.resample("h").count()
    fig, axis = plt.subplots(1, 1, figsize=(6, 4))
    axis.plot([f"{h}:00" for h in range(24)], crashes_time["COLLISION_ID"])
    axis.scatter([f"{h}:00" for h in range(24)], crashes_time["COLLISION_ID"], s=5)
    plt.subplots_adjust(
        left=0.138, right=0.998, top=0.88, bottom=0.11, wspace=0.2, hspace=0.2
    )
    axis.set_title("Hourly Crash Incidents in NYC [2012 - 2024]")
    axis.set_xlabel("Hour")
    axis.set_ylabel("Total Crash Incidents over 10 years")
    tick_visibility(axis, 3)
    axis.set_axisbelow(True)
    plt.grid(True)
    plt.savefig("crashes_by_time.pdf")
    plt.show()


if __name__ == "__main__":
    top_10_contributing_factors(df)
    boroughs_by_crashes(df)
    crashes_over_time(df)
    crashes_by_time(df)