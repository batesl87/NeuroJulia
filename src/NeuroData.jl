module NeuroData
    using JSON
    using Requests
    using DataFrames

    global token = ENV["JUPYTER_TOKEN"]
    global domain = ENV["NV_DOMAIN"] * ":8082/NeuroApi/datamovementservice/api/datamovement/"
    global homedir = "/home/jovyan/session/"

    type SqlQuery
        SourceMappingType
        SelectClause
        FromTableName
        FromSubQuery
        FromAlias
        Joins
        WhereClause
        GroupByClause
        HavingClause
        OrderByClause
        function SqlQuery(;select=nothing,tablename=nothing,subquery=nothing,alias=nothing,joins=nothing,where=nothing,groupby=nothing,having=nothing,orderby=nothing)
            return new(1,select,tablename,subquery,alias,joins,where,groupby,having,orderby)
        end
    end

    type SqlJoin
        JoinType
        JoinTableName
        JoinSubQuery
        JoinAlias
        JoinClause
        function SqlJoin(;jointype=nothing,tablename=nothing,subquery=nothing,alias=nothing,clause=nothing)
            return new(jointype,tablename,subquery,alias,clause)
        end
    end

    type DestinationFolder
        DestinationMappingType
        FolderPath
        function DestinationFolder(folderpath)
            if folderpath != nothing
                folderpath=strip(folderpath)
                startswith(folderpath,['/','\\']) ? folderpath = folderpath[2:length(folderpath)] : nothing
                !endswith(folderpath,['/','\\']) ? folderpath = folderpath * "/" : nothing
            else
                folderpath = ""
            end
            return new(0,folderpath)
        end
    end

    type TransferFromSqlToFileShareRequest
        FileShareDestinationDefinition::DestinationFolder
        SqlSourceDefinition::SqlQuery
    end

    function sqltofileshare(transferfromsqltofilesharerequest)
        url = domain * "TransferFromSqlToFileShare"
        msgdata = JSON.json(transferfromsqltofilesharerequest)
        msgdatalength = length(msgdata)
        headers = Dict("Content-Length" => string(msgdatalength), "Token" => token)
        response = post(url; headers=headers, data=msgdata)
        if response.status != 200
            if response.status == 401
                error("Session has expired: Log into Neuroverse and connect to your Notebooks session or reload the Notebooks page in Neuroverse")
            else
                error("Neuroverse connection error: Http code " * string(response.status))
            end
        end
        responseobj = JSON.parse(readstring(response))
        if responseobj["Error"] != nothing
            error("Neuroverse Error: " * responseobj["Error"])
        end
        filepath = homedir * transferfromsqltofilesharerequest.FileShareDestinationDefinition.FolderPath
        filepath = filepath * responseobj["FileName"] * ".info"

        keeplooping=true
        while keeplooping
            if isfile(filepath)
                sleep(0.25)
                open(filepath) do jsondata
                    d = JSON.parse(readstring(jsondata))
                    if d["Error"] == nothing
                        keeplooping=false
                    else
                        error("Neuroverse error: " * d["Error"])
                    end
                end
            end
            sleep(0.25)
        end
        rm(filepath)
        return responseobj["FileName"]
    end

    function sqltocsv(;folderpath=nothing,filename=nothing,sqlquery=nothing)
        fs=DestinationFolder(folderpath)
        folder=homedir * fs.FolderPath
        if isfile(folder * filename)
            error("File exists: " * folder * filename)
        end
        tr = TransferFromSqlToFileShareRequest(fs,sqlquery)
        outputname=sqltofileshare(tr)
        mv(folder * outputname, folder * filename)
        return folder * filename
    end

    function sqltodf(;sqlquery=nothing)
        fs=DestinationFolder(nothing)
        tr = TransferFromSqlToFileShareRequest(fs,sqlquery)
        outputname=sqltofileshare(tr)
        folder=homedir * fs.FolderPath
        df = readtable(folder * outputname)
        rm(folder * outputname)
        return df
    end
end